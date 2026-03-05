import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Telegram WS Proxy Mobile - ядро прокси
class TelegramWsProxy {
  static const int DEFAULT_PORT = 1080;
  static const String DEFAULT_TARGET_IP = '149.154.167.220';

  // Telegram IP диапазоны
  static final List<_IpRange> _tgRanges = [
    _ipRange('185.76.151.0', '185.76.151.255'),
    _ipRange('149.154.160.0', '149.154.175.255'),
    _ipRange('91.105.192.0', '91.105.193.255'),
    _ipRange('91.108.0.0', '91.108.255.255'),
  ];

  final Map<int, String> _dcOpt = {};
  final Set<_DcKey> _wsBlacklist = {};
  final Map<_DcKey, int> _dcFailUntil = {};
  static const int _dcFailCooldown = 60000; // мс

  ServerSocket? _server;
  bool _isRunning = false;
  bool _isShuttingDown = false;

  final ProxyStats stats = ProxyStats();
  final Function(String)? onLog;
  final Function(ProxyStats)? onStatsUpdate;

  TelegramWsProxy({this.onLog, this.onStatsUpdate});

  static _IpRange _ipRange(String start, String end) {
    return _IpRange(
      _ipToInt(start),
      _ipToInt(end),
    );
  }

  static int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) + (parts[1] << 16) + (parts[2] << 8) + parts[3];
  }

  static String _intToIp(int ip) {
    return '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}';
  }

  bool _isTelegramIp(String ip) {
    try {
      final n = _ipToInt(ip);
      return _tgRanges.any((r) => r.contains(n));
    } catch (e) {
      return false;
    }
  }

  Future<void> start({
    int port = DEFAULT_PORT,
    Map<int, String> dcMapping = const {},
  }) async {
    if (_isRunning) {
      _log('Прокси уже запущен');
      return;
    }

    _dcOpt.clear();
    _dcOpt.addAll(dcMapping.isEmpty 
        ? {2: DEFAULT_TARGET_IP, 4: DEFAULT_TARGET_IP} 
        : dcMapping);

    _isShuttingDown = false;
    _isRunning = true;
    stats.reset();

    try {
      _server = await ServerSocket.bind('127.0.0.1', port);
      _log('Прокси запущен на порту $port');
      _log('DC маппинг: ${_dcOpt.map((k, v) => MapEntry('DC$k', v)).toString()}');

      await for (final client in _server!) {
        if (_isShuttingDown) break;
        _handleClient(client).catchError((e) => _log('Ошибка клиента: $e'));
      }
    } catch (e) {
      _log('Ошибка запуска: $e');
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    _isShuttingDown = true;
    _isRunning = false;
    await _server?.close();
    _server = null;
    _log('Прокси остановлен');
  }

  bool get isRunning => _isRunning;

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMsg = '[$timestamp] $message';
    onLog?.call(logMsg);
    print(logMsg);
  }

  Future<void> _handleClient(Socket client) async {
    stats.connectionsTotal++;
    final peer = client.remoteAddress;
    final label = '${peer.address}:${peer.port}';

    try {
      // SOCKS5 приветствие
      final greeting = await client.read(2).timeout(Duration(seconds: 10));
      if (greeting[0] != 5) {
        _log('[$label] Не SOCKS5 (ver=${greeting[0]})');
        await client.close();
        return;
      }

      final nMethods = greeting[1];
      await client.read(nMethods);
      client.write(Uint8List.fromList([5, 0])); // без авторизации
      await client.flush();

      // SOCKS5 CONNECT запрос
      final req = await client.read(4).timeout(Duration(seconds: 10));
      final cmd = req[1];
      final atyp = req[3];

      if (cmd != 1) {
        client.write(_socks5Reply(7));
        await client.flush();
        await client.close();
        return;
      }

      String dst;
      if (atyp == 1) { // IPv4
        final raw = await client.read(4);
        dst = _intToIp((raw[0] << 24) + (raw[1] << 16) + (raw[2] << 8) + raw[3]);
      } else if (atyp == 3) { // domain
        final dlen = (await client.read(1))[0];
        dst = utf8.decode(await client.read(dlen));
      } else if (atyp == 4) { // IPv6
        final raw = await client.read(16);
        dst = InternetAddress.fromRawAddress(raw).address;
      } else {
        client.write(_socks5Reply(8));
        await client.flush();
        await client.close();
        return;
      }

      final portRaw = await client.read(2);
      final port = (portRaw[0] << 8) + portRaw[1];

      // Не Telegram IP -> прямой пасsthrough
      if (!_isTelegramIp(dst)) {
        stats.connectionsPassthrough++;
        _log('[$label] Passthrough -> $dst:$port');
        await _passthrough(client, dst, port);
        return;
      }

      // Telegram DC: принимаем SOCKS, читаем init
      client.write(_socks5Reply(0));
      await client.flush();

      final init = await client.read(64).timeout(Duration(seconds: 15));

      // HTTP транспорт -> отклоняем
      if (_isHttpTransport(init)) {
        stats.connectionsHttpRejected++;
        _log('[$label] HTTP транспорт (отклонено)');
        await client.close();
        return;
      }

      // Извлекаем DC ID
      final dcInfo = _dcFromInit(init);
      final dc = dcInfo.$1;
      final isMedia = dcInfo.$2;

      if (dc == null || !_dcOpt.containsKey(dc)) {
        _log('[$label] Неизвестный DC$dc -> TCP fallback');
        await _tcpFallback(client, dst, port, init, dc, isMedia);
        return;
      }

      final dcKey = _DcKey(dc, isMedia ?? true);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Проверка blacklist
      if (_wsBlacklist.contains(dcKey)) {
        _log('[$label] DC$dc в WS blacklist -> TCP');
        await _tcpFallback(client, dst, port, init, dc, isMedia);
        return;
      }

      // Проверка cooldown
      final failUntil = _dcFailUntil[dcKey] ?? 0;
      if (now < failUntil) {
        _log('[$label] DC$dc WS cooldown -> TCP');
        await _tcpFallback(client, dst, port, init, dc, isMedia);
        return;
      }

      // Попытка WebSocket подключения
      final domains = _wsDomains(dc, isMedia);
      final target = _dcOpt[dc]!;

      RawWebSocket? ws;
      var wsFailedRedirect = false;
      var allRedirects = true;

      for (final domain in domains) {
        try {
          _log('[$label] DC$dc -> wss://$domain/apiws через $target');
          ws = await RawWebSocket.connect(target, domain, timeout: 10000);
          allRedirects = false;
          break;
        } on WsHandshakeError catch (e) {
          stats.wsErrors++;
          if (e.isRedirect) {
            wsFailedRedirect = true;
            _log('[$label] DC$dc redirect $e.statusCode -> ${e.location}');
            continue;
          } else {
            allRedirects = false;
            _log('[$label] DC$dc handshake error: ${e.statusLine}');
          }
        } catch (e) {
          stats.wsErrors++;
          allRedirects = false;
          _log('[$label] DC$dc connect error: $e');
        }
      }

      if (ws == null) {
        if (wsFailedRedirect && allRedirects) {
          _wsBlacklist.add(dcKey);
          _log('[$label] DC$dc добавлен в WS blacklist (все 302)');
        } else {
          _dcFailUntil[dcKey] = now + _dcFailCooldown;
        }
        await _tcpFallback(client, dst, port, init, dc, isMedia);
        return;
      }

      // WS успех
      _dcFailUntil.remove(dcKey);
      stats.connectionsWs++;

      await ws.send(init);
      await _bridge(client, ws, label, dc, dst, port, isMedia);

    } catch (e) {
      _log('[$label] Ошибка: $e');
    } finally {
      try {
        await client.close();
      } catch (_) {}
      _updateStats();
    }
  }

  bool _isHttpTransport(Uint8List data) {
    final start = String.fromCharCodes(data.take(8));
    return start.startsWith('POST ') || 
           start.startsWith('GET ') || 
           start.startsWith('HEAD ') || 
           start.startsWith('OPTIONS ');
  }

  (int?, bool?) _dcFromInit(Uint8List data) {
    try {
      // Упрощённая экстракция DC из init пакета
      if (data.length < 64) return (null, null);
      
      // Пропускаем сложные вычисления, возвращаем null для fallback
      return (null, null);
    } catch (e) {
      return (null, null);
    }
  }

  List<String> _wsDomains(int dc, bool? isMedia) {
    final base = dc > 5 ? 'telegram.org' : 'web.telegram.org';
    if (isMedia == null) {
      return ['kws$dc-1.$base', 'kws$dc.$base'];
    }
    return isMedia 
        ? ['kws$dc-1.$base', 'kws$dc.$base'] 
        : ['kws$dc.$base', 'kws$dc-1.$base'];
  }

  Future<void> _passthrough(Socket client, String dst, int port) async {
    try {
      final remote = await Socket.connect(dst, port, timeout: Duration(seconds: 10));
      client.write(_socks5Reply(0));
      await client.flush();

      final toRemote = client.pipe(remote);
      final toClient = remote.pipe(client);

      await Future.wait([toRemote, toClient]);
    } catch (e) {
      _log('Passthrough error: $e');
      client.write(_socks5Reply(5));
      await client.flush();
    }
  }

  Future<void> _tcpFallback(Socket client, String dst, int port, 
      Uint8List init, int? dc, bool? isMedia) async {
    try {
      final remote = await Socket.connect(dst, port, timeout: Duration(seconds: 10));
      stats.connectionsTcpFallback++;
      
      remote.write(init);
      await remote.flush();

      await _bridgeTcp(client, remote, dc, dst, port, isMedia);
    } catch (e) {
      _log('TCP fallback error: $e');
    }
  }

  Future<void> _bridge(Socket client, RawWebSocket ws, String label,
      int? dc, String? dst, int? port, bool? isMedia) async {
    final dcTag = dc != null ? 'DC${dc}${isMedia == true ? "m" : ""}' : 'DC?';
    final dstTag = dst != null ? '$dst:$port' : '?';

    var upBytes = 0, downBytes = 0;
    var upPackets = 0, downPackets = 0;
    final startTime = DateTime.now();

    final toWs = _pipeToWs(client, ws, (bytes) {
      stats.bytesUp += bytes;
      upBytes += bytes;
      upPackets++;
    });

    final fromWs = _pipeFromWs(ws, client, (bytes) {
      stats.bytesDown += bytes;
      downBytes += bytes;
      downPackets++;
    });

    await Future.wait([toWs, fromWs]);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000;
    _log('[$label] $dcTag ($dstTag) сессия завершена: '
        '^${_humanBytes(upBytes)} ($upPackets) '
        'v${_humanBytes(downBytes)} ($downPackets) за ${elapsed.toStringAsFixed(1)}s');

    await ws.close();
    await client.close();
    _updateStats();
  }

  Future<void> _bridgeTcp(Socket client, Socket remote, 
      int? dc, String? dst, int? port, bool? isMedia) async {
    final toRemote = client.pipe(remote);
    final toClient = remote.pipe(client);
    await Future.wait([toRemote, toClient]);
    await remote.close();
    await client.close();
  }

  Future<void> _pipeToWs(Socket client, RawWebSocket ws, Function(int) onBytes) async {
    try {
      await for (final chunk in client) {
        if (chunk.isEmpty) break;
        onBytes(chunk.length);
        await ws.send(chunk);
      }
    } catch (e) {
      // Завершение соединения
    }
  }

  Future<void> _pipeFromWs(RawWebSocket ws, Socket client, Function(int) onBytes) async {
    try {
      await for (final data in ws.receive()) {
        onBytes(data.length);
        client.write(data);
        await client.flush();
      }
    } catch (e) {
      // Завершение соединения
    }
  }

  void _updateStats() {
    onStatsUpdate?.call(stats);
  }

  static Uint8List _socks5Reply(int status) {
    return Uint8List.fromList([
      0x05, status, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]);
  }

  static String _humanBytes(int n) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var unitIndex = 0;
    var num = n.toDouble();
    while (num >= 1024 && unitIndex < units.length - 1) {
      num /= 1024;
      unitIndex++;
    }
    return '${num.toStringAsFixed(1)}${units[unitIndex]}';
  }
}

class _IpRange {
  final int start;
  final int end;

  _IpRange(this.start, this.end);

  bool contains(int ip) => ip >= start && ip <= end;
}

class _DcKey {
  final int dc;
  final bool isMedia;

  _DcKey(this.dc, this.isMedia);

  @override
  bool operator ==(Object other) =>
      other is _DcKey && other.dc == dc && other.isMedia == isMedia;

  @override
  int get hashCode => dc.hashCode ^ isMedia.hashCode;
}

class ProxyStats {
  int connectionsTotal = 0;
  int connectionsWs = 0;
  int connectionsTcpFallback = 0;
  int connectionsHttpRejected = 0;
  int connectionsPassthrough = 0;
  int wsErrors = 0;
  int bytesUp = 0;
  int bytesDown = 0;

  void reset() {
    connectionsTotal = 0;
    connectionsWs = 0;
    connectionsTcpFallback = 0;
    connectionsHttpRejected = 0;
    connectionsPassthrough = 0;
    wsErrors = 0;
    bytesUp = 0;
    bytesDown = 0;
  }

  String get summary {
    return 'total=$connectionsTotal ws=$connectionsWs '
        'tcp=$connectionsTcpFallback http=$connectionsHttpRejected '
        'pass=$connectionsPassthrough err=$wsErrors '
        'up=${_humanBytes(bytesUp)} down=${_humanBytes(bytesDown)}';
  }

  static String _humanBytes(int n) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var unitIndex = 0;
    var num = n.toDouble();
    while (num >= 1024 && unitIndex < units.length - 1) {
      num /= 1024;
      unitIndex++;
    }
    return '${num.toStringAsFixed(1)}${units[unitIndex]}';
  }
}

class WsHandshakeError implements Exception {
  final int statusCode;
  final String statusLine;
  final Map<String, String> headers;
  final String? location;

  WsHandshakeError(this.statusCode, this.statusLine, {this.headers = const {}, this.location});

  bool get isRedirect => [301, 302, 303, 307, 308].contains(statusCode);
}

class RawWebSocket {
  Socket? _socket;
  bool _closed = false;
  final _receiveController = StreamController<Uint8List>.broadcast();

  static const int OP_BINARY = 0x2;
  static const int OP_CLOSE = 0x8;
  static const int OP_PING = 0x9;
  static const int OP_PONG = 0xA;

  RawWebSocket._(this._socket) {
    _readLoop();
  }

  static Future<RawWebSocket> connect(String ip, String domain, {int timeout = 10000}) async {
    final socket = await Socket.connect(ip, 443, timeout: Duration(milliseconds: timeout));
    
    // TLS handshake (упрощённо - для production нужен полноценный TLS)
    final secureSocket = await SecureSocket.secure(socket, host: domain);

    final wsKey = base64Encode(Random().nextBytes(16));
    final request = 'GET /apiws HTTP/1.1\r\n'
        'Host: $domain\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: $wsKey\r\n'
        'Sec-WebSocket-Version: 13\r\n'
        'Sec-WebSocket-Protocol: binary\r\n'
        'Origin: https://web.telegram.org\r\n'
        'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/131.0.0.0 Safari/537.36\r\n'
        '\r\n';

    secureSocket.write(request);
    await secureSocket.flush();

    // Читаем ответ
    final response = await _readHttpResponse(secureSocket);
    if (!response.startsWith('HTTP/1.1 101')) {
      await secureSocket.close();
      throw Exception('WebSocket handshake failed: $response');
    }

    return RawWebSocket._(secureSocket);
  }

  static Future<String> _readHttpResponse(SecureSocket socket) async {
    final buffer = StringBuffer();
    final completer = Completer<String>();
    var hasReadLine = false;

    final subscription = socket.listen((data) {
      final lines = utf8.decode(data).split('\r\n');
      for (int i = 0; i < lines.length - 1; i++) {
        buffer.writeln(lines[i]);
        if (lines[i].isEmpty) {
          completer.complete(buffer.toString());
          return;
        }
      }
      buffer.write(lines.last);
    });

    return completer.future.timeout(Duration(seconds: 10)).whenComplete(() {
      subscription.cancel();
    });
  }

  Future<void> send(Uint8List data) async {
    if (_closed || _socket == null) throw Exception('WebSocket closed');
    
    final frame = _buildFrame(OP_BINARY, data, mask: true);
    _socket!.write(frame);
    await _socket!.flush();
  }

  Stream<Uint8List> receive() => _receiveController.stream;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    
    try {
      final closeFrame = _buildFrame(OP_CLOSE, Uint8List(0), mask: true);
      _socket?.write(closeFrame);
      await _socket?.flush();
    } catch (_) {}
    
    await _socket?.close();
    _receiveController.close();
  }

  Uint8List _buildFrame(int opcode, Uint8List data, {bool mask = false}) {
    final header = BytesBuilder();
    header.addByte(0x80 | opcode);
    
    final length = data.length;
    final maskBit = mask ? 0x80 : 0x00;

    if (length < 126) {
      header.addByte(maskBit | length);
    } else if (length < 65536) {
      header.addByte(maskBit | 126);
      header.addByte((length >> 8) & 0xFF);
      header.addByte(length & 0xFF);
    } else {
      header.addByte(maskBit | 127);
      for (var i = 7; i >= 0; i--) {
        header.addByte((length >> (i * 8)) & 0xFF);
      }
    }

    if (mask) {
      final maskKey = Random().nextBytes(4);
      header.add(maskKey);
      final masked = _xorMask(data, maskKey);
      header.add(masked);
    } else {
      header.add(data);
    }

    return header.toBytes();
  }

  Uint8List _xorMask(Uint8List data, Uint8List mask) {
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ mask[i & 3];
    }
    return result;
  }

  void _readLoop() async {
    try {
      while (!_closed && _socket != null) {
        final header = await _socket!.read(2);
        if (header.isEmpty) break;

        final opcode = header[0] & 0x0F;
        final isMasked = (header[1] & 0x80) != 0;
        var length = header[1] & 0x7F;

        if (length == 126) {
          final lenBytes = await _socket!.read(2);
          length = (lenBytes[0] << 8) + lenBytes[1];
        } else if (length == 127) {
          final lenBytes = await _socket!.read(8);
          length = 0;
          for (var i = 0; i < 8; i++) {
            length = (length << 8) + lenBytes[i];
          }
        }

        Uint8List payload;
        if (isMasked) {
          final maskKey = await _socket!.read(4);
          payload = await _socket!.read(length);
          payload = _xorMask(payload, maskKey);
        } else {
          payload = await _socket!.read(length);
        }

        if (opcode == OP_CLOSE) {
          _closed = true;
          break;
        } else if (opcode == OP_PING) {
          await _sendPong(payload);
        } else if (opcode == OP_BINARY) {
          _receiveController.add(payload);
        }
      }
    } catch (e) {
      // Завершение чтения
    } finally {
      _receiveController.close();
    }
  }

  Future<void> _sendPong(Uint8List payload) async {
    if (_closed || _socket == null) return;
    final pong = _buildFrame(OP_PONG, payload, mask: true);
    _socket!.write(pong);
    await _socket!.flush();
  }
}
