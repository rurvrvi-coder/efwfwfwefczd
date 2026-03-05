import 'package:flutter/foundation.dart';
import 'proxy_core.dart';
import 'config.dart';

class ProxyProvider extends ChangeNotifier {
  TelegramWsProxy? _proxy;
  AppConfig _config = AppConfig();
  bool _isRunning = false;
  bool _isStarting = false;
  final List<String> _logs = [];
  ProxyStats _stats = ProxyStats();

  bool get isRunning => _isRunning;
  bool get isStarting => _isStarting;
  AppConfig get config => _config;
  List<String> get logs => List.unmodifiable(_logs);
  ProxyStats get stats => _stats;

  Future<void> loadConfig() async {
    _config = await AppConfig.load();
    notifyListeners();
  }

  Future<void> saveConfig(AppConfig newConfig) async {
    await newConfig.save();
    _config = newConfig;
    notifyListeners();
  }

  Future<void> startProxy() async {
    if (_isRunning || _isStarting) return;

    _isStarting = true;
    _logs.clear();
    notifyListeners();

    try {
      _proxy = TelegramWsProxy(
        onLog: (msg) {
          _logs.add(msg);
          if (_logs.length > 100) _logs.removeAt(0);
          notifyListeners();
        },
        onStatsUpdate: (stats) {
          _stats = stats;
          notifyListeners();
        },
      );

      await _proxy!.start(
        port: _config.port,
        dcMapping: _config.dcMapping,
      );

      _isRunning = true;
      _isStarting = false;
      notifyListeners();
    } catch (e) {
      _isStarting = false;
      _logs.add('Ошибка запуска: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopProxy() async {
    await _proxy?.stop();
    _isRunning = false;
    _isStarting = false;
    notifyListeners();
  }

  Future<void> restartProxy() async {
    await stopProxy();
    await Future.delayed(const Duration(milliseconds: 500));
    await startProxy();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _proxy?.stop();
    super.dispose();
  }
}
