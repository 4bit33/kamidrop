import 'package:flutter/material.dart';

import '../settings.dart';
import '../theme.dart';
import '../update/update_controller.dart';

/// Налаштування застосунку. Кожна зміна зберігається одразу.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.updates});

  final KamiSettings settings;
  final UpdateController? updates; // null — без розділу оновлень (напр. у тестах)

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
          if (widget.updates != null) ...[
            const Divider(height: 24),
            SwitchListTile(
              title: const Text('Перевіряти оновлення'),
              subtitle: const Text('Раз на добу дивитися, чи є нова версія KamiDrop. '
                  'Встановлення — лише після твого натискання'),
              value: s.checkUpdates,
              activeThumbColor: Kami.shu,
              onChanged: (v) => _set(() => s.checkUpdates = v),
            ),
            ListenableBuilder(
              listenable: widget.updates!,
              builder: (context, _) {
                final u = widget.updates!;
                final status = switch (u.state) {
                  UpdateState.checking => 'Перевіряю…',
                  UpdateState.upToDate => 'Встановлено найновішу версію',
                  UpdateState.available ||
                  UpdateState.downloading ||
                  UpdateState.installing =>
                    'Є версія ${u.info?.version} — оновити можна на головному екрані',
                  UpdateState.error => u.message ?? 'Помилка',
                  UpdateState.idle => null,
                };
                return ListTile(
                  title: Text('Версія ${u.currentVersion ?? '—'}'),
                  subtitle: status == null ? null : Text(status),
                  trailing: TextButton(
                    onPressed: u.state == UpdateState.checking ? null : () => u.check(force: true),
                    child: const Text('Перевірити'),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
