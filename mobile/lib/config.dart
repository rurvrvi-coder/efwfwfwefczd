import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _keyPort = 'port';
  static const String _keyDcIp = 'dc_ip';
  static const String _keyVerbose = 'verbose';
  static const String _keyAutoStart = 'auto_start';

  int port;
  List<String> dcIp;
  bool verbose;
  bool autoStart;

  AppConfig({
    this.port = 1080,
    this.dcIp = const ['2:149.154.167.220', '4:149.154.167.220'],
    this.verbose = false,
    this.autoStart = false,
  });

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(
      port: prefs.getInt(_keyPort) ?? 1080,
      dcIp: prefs.getStringList(_keyDcIp) ?? 
            ['2:149.154.167.220', '4:149.154.167.220'],
      verbose: prefs.getBool(_keyVerbose) ?? false,
      autoStart: prefs.getBool(_keyAutoStart) ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPort, port);
    await prefs.setStringList(_keyDcIp, dcIp);
    await prefs.setBool(_keyVerbose, verbose);
    await prefs.setBool(_keyAutoStart, autoStart);
  }

  Map<int, String> get dcMapping {
    final map = <int, String>{};
    for (final entry in dcIp) {
      if (entry.contains(':')) {
        final parts = entry.split(':');
        final dc = int.tryParse(parts[0]);
        final ip = parts[1];
        if (dc != null && ip.isNotEmpty) {
          map[dc] = ip;
        }
      }
    }
    return map.isEmpty ? {2: '149.154.167.220', 4: '149.154.167.220'} : map;
  }

  AppConfig copyWith({
    int? port,
    List<String>? dcIp,
    bool? verbose,
    bool? autoStart,
  }) {
    return AppConfig(
      port: port ?? this.port,
      dcIp: dcIp ?? this.dcIp,
      verbose: verbose ?? this.verbose,
      autoStart: autoStart ?? this.autoStart,
    );
  }

  String toJson() => jsonEncode({
    'port': port,
    'dc_ip': dcIp,
    'verbose': verbose,
    'auto_start': autoStart,
  });

  factory AppConfig.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return AppConfig(
      port: data['port'] ?? 1080,
      dcIp: List<String>.from(data['dc_ip'] ?? []),
      verbose: data['verbose'] ?? false,
      autoStart: data['auto_start'] ?? false,
    );
  }
}
