import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'proxy_provider.dart';
import 'config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _portController;
  late TextEditingController _dcController;
  late bool _verbose;

  @override
  void initState() {
    super.initState();
    final config = context.read<ProxyProvider>().config;
    _portController = TextEditingController(text: config.port.toString());
    _dcController = TextEditingController(text: config.dcIp.join('\n'));
    _verbose = config.verbose;
  }

  @override
  void dispose() {
    _portController.dispose();
    _dcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Порт прокси',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '1080',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DC → IP маппинги',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Формат: DC:IP (по одному на строку)',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dcController,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '2:149.154.167.220\n4:149.154.167.220',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                title: const Text('Подробное логирование'),
                subtitle: const Text('Debug режим'),
                value: _verbose,
                onChanged: (v) => setState(() => _verbose = v),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Сохранить настройки'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Изменения вступят в силу после перезапуска прокси.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Порт должен быть 1-65535')),
      );
      return;
    }

    final lines = _dcController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines) {
      if (!line.contains(':')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка в строке: $line (формат DC:IP)')),
        );
        return;
      }
    }

    final provider = context.read<ProxyProvider>();
    final newConfig = provider.config.copyWith(
      port: port,
      dcIp: lines,
      verbose: _verbose,
    );

    provider.saveConfig(newConfig);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Настройки сохранены'),
        action: SnackBarAction(
          label: 'Перезапустить',
          onPressed: () => provider.restartProxy(),
        ),
      ),
    );
  }
}
