import 'package:flutter/material.dart';

import '../settings.dart';
import '../theme.dart';
import '../update/update_controller.dart';
import '../l10n/l10n.dart';

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
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Мова: за системою або вибрана вручну. Назви мов — кожна своєю мовою.
          ListTile(
            title: Text(l10n.language),
            trailing: DropdownButton<String>(
              value: s.language,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem)),
                const DropdownMenuItem(value: 'uk', child: Text('Українська')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) {
                if (v == null) return;
                _set(() => s.language = v);
                appLanguage.value = v;
              },
            ),
          ),
          const Divider(height: 8),
          SwitchListTile(
            title: Text(l10n.autoOpenTitle),
            subtitle: Text(l10n.autoOpenSubtitle),
            value: s.autoOpenShared,
            activeThumbColor: Kami.shu,
            onChanged: (v) => _set(() => s.autoOpenShared = v),
          ),
          SwitchListTile(
            title: Text(l10n.lastFirstTitle),
            subtitle: Text(l10n.lastFirstSubtitle),
            value: s.lastPrinterFirst,
            activeThumbColor: Kami.shu,
            onChanged: (v) => _set(() => s.lastPrinterFirst = v),
          ),
          SwitchListTile(
            title: Text(l10n.rememberLayoutTitle),
            subtitle: Text(l10n.rememberLayoutSubtitle),
            value: s.rememberLayout,
            activeThumbColor: Kami.shu,
            onChanged: (v) => _set(() => s.rememberLayout = v),
          ),
          if (widget.updates != null) ...[
            const Divider(height: 24),
            SwitchListTile(
              title: Text(l10n.checkUpdatesTitle),
              subtitle: Text(l10n.checkUpdatesSubtitle),
              value: s.checkUpdates,
              activeThumbColor: Kami.shu,
              onChanged: (v) => _set(() => s.checkUpdates = v),
            ),
            ListenableBuilder(
              listenable: widget.updates!,
              builder: (context, _) {
                final u = widget.updates!;
                final status = switch (u.state) {
                  UpdateState.checking => l10n.checking,
                  UpdateState.upToDate => l10n.upToDate,
                  UpdateState.available ||
                  UpdateState.downloading ||
                  UpdateState.installing =>
                    l10n.updateOnMainScreen(u.info?.version ?? ''),
                  UpdateState.error => u.message ?? l10n.error,
                  UpdateState.idle => null,
                };
                return ListTile(
                  title: Text(l10n.versionLabel(u.currentVersion ?? '—')),
                  subtitle: status == null ? null : Text(status),
                  trailing: TextButton(
                    onPressed: u.state == UpdateState.checking ? null : () => u.check(force: true),
                    child: Text(l10n.check),
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
