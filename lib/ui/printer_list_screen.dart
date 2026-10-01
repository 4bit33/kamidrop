import 'package:flutter/material.dart';

import '../discovery/discovery.dart';
import '../printing/capabilities.dart';
import '../settings.dart';
import '../update/update_controller.dart';
import '../theme.dart';
import 'print_sheet.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class PrinterListScreen extends StatefulWidget {
  const PrinterListScreen({
    super.key,
    required this.discovery,
    required this.sharedFile,
    required this.settings,
    required this.updates,
  });

  final PrinterDiscovery discovery;
  final ValueNotifier<String?> sharedFile;
  final KamiSettings settings;
  final UpdateController updates;

  @override
  State<PrinterListScreen> createState() => _PrinterListScreenState();
}

class _PrinterListScreenState extends State<PrinterListScreen> {
  PrinterDiscovery get discovery => widget.discovery;
  ValueNotifier<String?> get sharedFile => widget.sharedFile;

  String? _autoOpenedFor; // файл, для якого аркуш друку вже відкривали самі
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    discovery.addListener(_maybeAutoOpen);
    sharedFile.addListener(_maybeAutoOpen);
  }

  @override
  void didUpdateWidget(PrinterListScreen old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) _maybeAutoOpen(); // налаштування довантажилися пізніше за файл
  }

  @override
  void dispose() {
    discovery.removeListener(_maybeAutoOpen);
    sharedFile.removeListener(_maybeAutoOpen);
    super.dispose();
  }

  /// Останній використаний принтер — першим.
  List<DiscoveredPrinter> get _printers {
    final list = discovery.printers;
    if (!widget.settings.lastPrinterFirst) return list;
    final last = widget.settings.lastPrinterId;
    final i = list.indexWhere((p) => p.id == last);
    if (i > 0) list.insert(0, list.removeAt(i));
    return list;
  }

  /// Файл прийшов через «Поділитися»: якщо ясно, на чому друкувати (останній принтер на зв'язку
  /// або він узагалі один), одразу відкриваємо аркуш друку.
  void _maybeAutoOpen() {
    final path = sharedFile.value;
    if (!widget.settings.autoOpenShared) return;
    if (path == null || path == _autoOpenedFor || _sheetOpen || !mounted) return;
    final ready = discovery.printers.where((p) => p.capabilities != null).toList();
    final last = ready.where((p) => p.id == widget.settings.lastPrinterId).firstOrNull;
    final target = last ?? (ready.length == 1 && discovery.printers.length == 1 ? ready.single : null);
    if (target == null) return;
    _autoOpenedFor = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_sheetOpen) _openSheet(target);
    });
  }

  /// Сканування; «Друк» зі скану кладе PDF як файл із «Поділитися» — далі вибираєш принтер.
  Future<void> _openScan(DiscoveredPrinter p) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ScanScreen(printer: p, settings: widget.settings, onPrint: (path) => sharedFile.value = path),
      ));

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(settings: widget.settings, updates: widget.updates)),
    );
    if (mounted) setState(() {});
    _maybeAutoOpen();
  }

  Future<void> _openSheet(DiscoveredPrinter p) async {
    _sheetOpen = true;
    try {
      await showPrintSheet(context, discovery, widget.settings, p, initialPath: sharedFile.value);
    } finally {
      _sheetOpen = false;
    }
    if (mounted) setState(() {}); // останній принтер міг змінитися
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([discovery, sharedFile, widget.updates]),
          builder: (context, _) {
            final printers = _printers;
            final shared = sharedFile.value;
            return RefreshIndicator(
              color: Kami.shu,
              onRefresh: discovery.scan,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                children: [
                  _Header(scanning: discovery.scanning, onRefresh: discovery.scan, onSettings: _openSettings),
                  const SizedBox(height: 28),
                  if (widget.updates.bannerVisible) ...[
                    _UpdateBanner(updates: widget.updates),
                    const SizedBox(height: 16),
                  ],
                  if (shared != null) ...[
                    _SharedFileBanner(path: shared, onClose: () => sharedFile.value = null),
                    const SizedBox(height: 16),
                  ],
                  if (printers.isEmpty) _EmptyState(scanning: discovery.scanning, error: discovery.lastError),
                  for (final p in printers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PrinterCard(
                        printer: p,
                        isLast: widget.settings.lastPrinterFirst &&
                            p.id == widget.settings.lastPrinterId &&
                            printers.length > 1,
                        onTap: () => _openSheet(p),
                        onScan: p.scanner == null ? null : () => _openScan(p),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addByIp(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Додати принтер за IP-адресою'),
                      style: TextButton.styleFrom(foregroundColor: Kami.stone),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _addByIp(BuildContext context) async {
    final ip = await showDialog<String>(context: context, builder: (_) => const _AddPrinterDialog());
    if (ip != null && ip.isNotEmpty) await discovery.addManual(ip);
  }
}

/// Діалог має власний State, щоб контролер поля жив рівно стільки, скільки сам діалог
/// (включно з анімацією закриття).
class _AddPrinterDialog extends StatefulWidget {
  const _AddPrinterDialog();

  @override
  State<_AddPrinterDialog> createState() => _AddPrinterDialogState();
}

class _AddPrinterDialogState extends State<_AddPrinterDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Kami.paper,
      title: const Text('Принтер за IP'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '192.168.1.50'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Додати')),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scanning, required this.onRefresh, required this.onSettings});

  final bool scanning;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // Печатка-ханко з ієрогліфом 紙 («папір», «камі»).
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: Kami.shu, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: const Text('紙', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('KamiDrop', style: theme.textTheme.headlineMedium),
              Text(scanning ? 'Шукаю принтери поруч…' : 'Принтери поруч', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (scanning)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Kami.stone)),
          )
        else
          IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh, color: Kami.stone), tooltip: 'Шукати знову'),
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.tune, color: Kami.stone),
          tooltip: 'Налаштування',
        ),
      ],
    );
  }
}

/// Файл, що прийшов через «Поділитися»: лишається вибраним, поки його не закриють.
class _SharedFileBanner extends StatelessWidget {
  const _SharedFileBanner({required this.path, required this.onClose});

  final String path;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = path.split('/').last;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: Kami.shu.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Kami.shu.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: Kami.shu),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('Вибери принтер нижче', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Kami.stone), tooltip: 'Прибрати файл'),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, this.error});

  final bool scanning;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.print_outlined, size: 40, color: Kami.stone.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(scanning ? 'Шукаю принтери…' : 'Принтерів поки не видно', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            error ?? 'Переконайся, що принтер увімкнений і в тій самій Wi-Fi мережі.\n'
                'Потягни список донизу, щоб шукати знову.',
            style: small,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class PrinterCard extends StatelessWidget {
  const PrinterCard({super.key, required this.printer, required this.onTap, this.isLast = false, this.onScan});

  final DiscoveredPrinter printer;
  final VoidCallback onTap;
  final bool isLast; // останній використаний — позначаємо, якщо принтерів кілька
  final VoidCallback? onScan; // є сканер — показуємо «Сканувати»

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = printer.capabilities;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(printer: printer),
                  const SizedBox(width: 10),
                  Expanded(child: Text(printer.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                  if (isLast)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('останній', style: theme.textTheme.bodySmall?.copyWith(color: Kami.shu)),
                    ),
                  const Icon(Icons.chevron_right, color: Kami.stone),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Text(
                  [if (caps != null && caps.model != printer.name) caps.model, printer.host].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (caps != null && caps.recentlyRestarted)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 4),
                  child: Text('Щойно ввімкнувся — може ще прогріватися',
                      style: theme.textTheme.bodySmall?.copyWith(color: Kami.kincha)),
                ),
              if (printer.loading && caps == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 2, color: Kami.stone, backgroundColor: Kami.line),
                ),
              if (printer.error != null && caps == null)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 20),
                  child: Text(printer.error!, style: theme.textTheme.bodySmall?.copyWith(color: Kami.shu)),
                ),
              if (caps != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Chip(label: Text(caps.supportsColor ? 'Колір' : 'Ч/Б')),
                    if (caps.supportsDuplex) const Chip(label: Text('Двосторонній')),
                    Chip(label: Text('${caps.defaultDpi} dpi')),
                  ],
                ),
                if (caps.markers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MarkerLevels(markers: caps.markers),
                ],
              ],
              if (onScan != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onScan,
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text('Сканувати'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.printer});

  final DiscoveredPrinter printer;

  @override
  Widget build(BuildContext context) {
    final caps = printer.capabilities;
    final color = printer.error != null
        ? Kami.shu
        : switch (caps?.state) {
            PrinterState.idle => Kami.matcha,
            PrinterState.processing => Kami.kincha,
            PrinterState.stopped => Kami.shu,
            _ => Kami.line,
          };
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class MarkerLevels extends StatelessWidget {
  const MarkerLevels({super.key, required this.markers});

  final List<Marker> markers;

  static Color _parse(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (v == null) return Kami.sumi;
    final c = Color(0xFF000000 | v);
    // Деякі принтери повідомляють чорний тонер як #FFFFFF — на світлому тлі це невидимо.
    if (v == 0xFFFFFF) return Kami.sumi;
    // Жовтий на папері васі зливається — трохи притемнюємо світлі кольори.
    return c.computeLuminance() > 0.6 ? Color.lerp(c, Kami.sumi, 0.15)! : c;
  }

  static String _label(String name) {
    final short = name.split('_').first.trim();
    return short.length > 14 ? '${short.substring(0, 14)}…' : short;
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      children: [
        for (final m in markers)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(_label(m.name), style: small, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: m.level < 0 ? null : m.level / 100,
                      minHeight: 5,
                      color: _parse(m.color),
                      backgroundColor: Kami.line,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    m.level < 0 ? '?' : '${m.level}%',
                    style: small?.copyWith(color: m.isLow ? Kami.shu : null),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// «Є нова версія» — з кнопкою оновлення й прогресом завантаження.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.updates});

  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = updates.info!;
    final (text, busy) = switch (updates.state) {
      UpdateState.downloading => ('Завантажую версію ${info.version}… ${(updates.progress * 100).round()} %', true),
      UpdateState.installing => ('Встановлюю версію ${info.version}…', true),
      _ => ('Є нова версія ${info.version}', false),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        color: Kami.shu.withValues(alpha: 0.06),
        border: Border.all(color: Kami.shu.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_outlined, color: Kami.shu, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.titleSmall)),
              if (!busy)
                IconButton(
                  onPressed: updates.dismiss,
                  icon: const Icon(Icons.close, size: 18, color: Kami.stone),
                  tooltip: 'Пізніше',
                ),
            ],
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: LinearProgressIndicator(
                value: updates.state == UpdateState.downloading ? updates.progress : null,
                minHeight: 2,
                color: Kami.shu,
                backgroundColor: Kami.line,
              ),
            ),
          if (updates.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(updates.message!, style: theme.textTheme.bodySmall?.copyWith(color: Kami.shu)),
            ),
          if (!busy)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: updates.install, child: const Text('Оновити')),
            ),
        ],
      ),
    );
  }
}
