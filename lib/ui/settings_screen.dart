import 'dart:io';

import 'package:flutter/material.dart';

import '../settings.dart';
import '../theme.dart';
import '../update/update_controller.dart';
import '../l10n/l10n.dart';
import '../platform/platform_bridge.dart';
import '../printproxy/proxy_host.dart';

/// Налаштування застосунку. Кожна зміна зберігається одразу.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.updates, this.proxy});

  final KamiSettings settings;
  final UpdateController? updates; // null — без розділу оновлень (напр. у тестах)
  final PrintProxyHost? proxy; // Windows: принтери KamiDrop у системі; null — розділу немає

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  KamiSettings get s => widget.settings;

  void _set(void Function() change) {
    setState(change);
    s.save();
  }

  List<String> _pcPrinters = const []; // наші принтери, що вже є у Windows
  bool _pcBusy = false;

  @override
  void initState() {
    super.initState();
    if (widget.proxy != null) _refreshPcPrinters();
  }

  Future<void> _refreshPcPrinters() async {
    final names = await PrintProxyHost.installed();
    if (!mounted) return;
    setState(() => _pcPrinters = names);
    // Є принтери в системі — KamiDrop має жити у фоні: автозапуск і трей.
    PrintProxyHost.setAutostart(names.isNotEmpty);
    if (s.pcPrinters != names.isNotEmpty) {
      s.pcPrinters = names.isNotEmpty;
      s.save();
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pcBusyWhile(Future<void> Function() work) async {
    setState(() => _pcBusy = true);
    try {
      await work();
      await _refreshPcPrinters();
    } finally {
      if (mounted) setState(() => _pcBusy = false);
    }
  }

  Future<void> _addPcPrinters() => _pcBusyWhile(() async {
        final proxy = widget.proxy!;
        final added = await proxy.addToSystem();
        if (!mounted) return;
        if (added == null) return _snack(l10n.pcPrintersFailed);
        // Той самий апарат через драйвер виробника тепер дублюється — пропонуємо прибрати.
        final dups = await proxy.duplicates();
        if (!mounted || dups.isEmpty) return;
        final remove = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.pcDuplicatesTitle),
            content: Text(l10n.pcDuplicatesBody(dups.join('\n'))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.no)),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.remove)),
            ],
          ),
        );
        if (remove == true && !await PrintProxyHost.removeFromSystem(dups) && mounted) _snack(l10n.pcPrintersFailed);
      });

  Future<void> _removePcPrinters() => _pcBusyWhile(() async {
        if (!await PrintProxyHost.removeFromSystem(_pcPrinters) && mounted) _snack(l10n.pcPrintersFailed);
      });

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
          if (Platform.isAndroid) ...[
            ListTile(
              leading: const Icon(Icons.print_outlined, color: Kami.shu),
              title: Text(l10n.printServiceTitle),
              subtitle: Text(l10n.printServiceSubtitle),
              trailing: const Icon(Icons.open_in_new, size: 18, color: Kami.stone),
              onTap: PlatformBridge.openPrintSettings,
            ),
            const Divider(height: 8),
          ],
          if (widget.proxy != null) ...[
            ListTile(
              leading: const Icon(Icons.print_outlined, color: Kami.shu),
              title: Text(l10n.pcPrintersTitle),
              subtitle: Text(
                _pcPrinters.isEmpty ? l10n.pcPrintersSubtitle : l10n.pcPrintersActive(_pcPrinters.join(', ')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 64, right: 16),
              child: _pcBusy
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Row(children: [
                      TextButton(onPressed: _addPcPrinters, child: Text(l10n.add)),
                      if (_pcPrinters.isNotEmpty) TextButton(onPressed: _removePcPrinters, child: Text(l10n.remove)),
                    ]),
            ),
            const Divider(height: 8),
          ],
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
