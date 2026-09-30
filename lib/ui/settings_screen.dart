import 'package:flutter/material.dart';

import '../settings.dart';
import '../theme.dart';

/// Налаштування застосунку. Кожна зміна зберігається одразу.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final KamiSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  KamiSettings get s => widget.settings;

  void _set(void Function() change) {
    setState(change);
    s.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Налаштування')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            title: const Text('Одразу відкривати друк'),
            subtitle: const Text('Файл із «Поділитися» відкривається на останньому принтері '
                '(або на єдиному, якщо він один)'),
            value: s.autoOpenShared,
            activeThumbColor: Kami.shu,
            onChanged: (v) => _set(() => s.autoOpenShared = v),
          ),
          SwitchListTile(
            title: const Text('Останній принтер першим'),
            subtitle: const Text('Ставити принтер, на якому друкував востаннє, на початок списку'),
            value: s.lastPrinterFirst,
            activeThumbColor: Kami.shu,
            onChanged: (v) => _set(() => s.lastPrinterFirst = v),
          ),
          SwitchListTile(
            title: const Text('Пам\'ятати макет'),
            subtitle: const Text('Фото й документи відкриваються з макетом минулого друку, '
                'а не з типовим'),
            value: s.rememberLayout,
            activeThumbColor: Kami.shu,
            onChanged: (v) => _set(() => s.rememberLayout = v),
          ),
        ],
      ),
    );
  }
}
