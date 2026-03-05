import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'proxy_provider.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => context.read<ProxyProvider>().clearLogs(),
            tooltip: 'Очистить',
          ),
        ],
      ),
      body: Consumer<ProxyProvider>(
        builder: (context, provider, _) {
          final logs = provider.logs;

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.subject_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Логи пусты',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: logs.length,
            itemBuilder: (_, i) {
              return SelectableText(
                logs[i],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
