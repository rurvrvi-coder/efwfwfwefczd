import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'proxy_provider.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'logs_screen.dart';

void main() {
  runApp(const TgWsProxyApp());
}

class TgWsProxyApp extends StatelessWidget {
  const TgWsProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProxyProvider()..loadConfig(),
      child: MaterialApp(
        title: 'TG WS Proxy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3390ec),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3390ec),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TG WS Proxy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Consumer<ProxyProvider>(
                builder: (context, provider, _) {
                  final isRunning = provider.isRunning;
                  final isStarting = provider.isStarting;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            isRunning ? Icons.check_circle : Icons.cloud_off,
                            size: 80,
                            color: isRunning
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isRunning
                                ? 'Прокси работает'
                                : isStarting
                                    ? 'Запуск...'
                                    : 'Остановлен',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Порт: ${provider.config.port}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!isRunning && !isStarting)
                                ElevatedButton.icon(
                                  onPressed: () => provider.startProxy(),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Запустить'),
                                ),
                              if (isRunning)
                                ElevatedButton.icon(
                                  onPressed: () => provider.stopProxy(),
                                  icon: const Icon(Icons.stop),
                                  label: const Text('Остановить'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.error,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              if (isStarting)
                                const CircularProgressIndicator(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Stats Preview
              Consumer<ProxyProvider>(
                builder: (context, provider, _) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Статистика',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      )),
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const StatsScreen()),
                                ),
                                child: const Text('Подробнее'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _StatItem(
                                  '↑',
                                  _humanBytes(provider.stats.bytesUp),
                                ),
                              ),
                              Expanded(
                                child: _StatItem(
                                  '↓',
                                  _humanBytes(provider.stats.bytesDown),
                                ),
                              ),
                              Expanded(
                                child: _StatItem(
                                  'WS',
                                  '${provider.stats.connectionsWs}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Actions
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.file_present_outlined),
                      title: const Text('Логи'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('О приложении'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showAboutDialog(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'TG WS Proxy',
      applicationVersion: '1.0.0',
      children: [
        const Text('SOCKS5-прокси для Telegram с WebSocket поддержкой.'),
        const SizedBox(height: 16),
        const Text('Подключение: Настройки → Продвинутые → Прокси → SOCKS5 127.0.0.1:1080'),
      ],
    );
  }

  String _humanBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var num = bytes.toDouble();
    var i = 0;
    while (num >= 1024 && i < units.length - 1) {
      num /= 1024;
      i++;
    }
    return '${num.toStringAsFixed(1)} ${units[i]}';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
