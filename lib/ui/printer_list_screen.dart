import 'package:flutter/material.dart';

import '../discovery/discovery.dart';
import '../printing/capabilities.dart';
import '../theme.dart';
import 'print_sheet.dart';

class PrinterListScreen extends StatelessWidget {
  const PrinterListScreen({super.key, required this.discovery, required this.sharedFile});

  final PrinterDiscovery discovery;
  final ValueNotifier<String?> sharedFile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([discovery, sharedFile]),
          builder: (context, _) {
            final printers = discovery.printers;
            final shared = sharedFile.value;
            return RefreshIndicator(
              color: Kami.shu,
              onRefresh: discovery.scan,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                children: [
                  _Header(scanning: discovery.scanning, onRefresh: discovery.scan),
                  const SizedBox(height: 28),
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
                        onTap: () => showPrintSheet(context, discovery, p, initialPath: shared),
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
        decoration: const InputDecoration(hintText: '192.168.0.78'),
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
  const _Header({required this.scanning, required this.onRefresh});

  final bool scanning;
  final VoidCallback onRefresh;

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
  const PrinterCard({super.key, required this.printer, required this.onTap});

  final DiscoveredPrinter printer;
  final VoidCallback onTap;

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
