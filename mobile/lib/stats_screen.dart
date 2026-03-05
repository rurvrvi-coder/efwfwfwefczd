import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'proxy_provider.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика'),
      ),
      body: Consumer<ProxyProvider>(
        builder: (context, provider, _) {
          final stats = provider.stats;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatCard(
                  'Подключения',
                  [
                    _StatRow('Всего', stats.connectionsTotal),
                    _StatRow('WebSocket', stats.connectionsWs),
                    _StatRow('TCP fallback', stats.connectionsTcpFallback),
                    _StatRow('HTTP (отклонено)', stats.connectionsHttpRejected),
                    _StatRow('Passthrough', stats.connectionsPassthrough),
                  ],
                ),
                const SizedBox(height: 16),
                _StatCard(
                  'Трафик',
                  [
                    _StatRow('Исходящий ↑', stats.bytesUp, isBytes: true),
                    _StatRow('Входящий ↓', stats.bytesDown, isBytes: true),
                  ],
                ),
                const SizedBox(height: 16),
                _StatCard(
                  'Ошибки',
                  [
                    _StatRow('WS ошибки', stats.wsErrors),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => provider.clearLogs(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Сбросить статистику'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _StatCard(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int value;
  final bool isBytes;

  const _StatRow(this.label, this.value, {this.isBytes = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            isBytes ? _humanBytes(value) : value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
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
