import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../discovery/discovery.dart';
import '../platform/platform_bridge.dart';
import '../printing/collage.dart';
import '../printing/compose.dart';
import '../printing/print_service.dart';
import '../printing/sources.dart';
import '../settings.dart';
import '../theme.dart';
import 'collage_editor.dart';
import 'layout_editor.dart';

Future<void> showPrintSheet(
  BuildContext context,
  PrinterDiscovery discovery,
  KamiSettings settings,
  DiscoveredPrinter printer, {
  String? initialPath,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PrintSheet(discovery: discovery, settings: settings, printer: printer, initialPath: initialPath),
  );
}

class PrintSheet extends StatefulWidget {
  const PrintSheet({
    super.key,
    required this.discovery,
    required this.settings,
    required this.printer,
    this.initialPath,
  });

  final PrinterDiscovery discovery;
  final KamiSettings settings;
  final DiscoveredPrinter printer;
  final String? initialPath;

  @override
  State<PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends State<PrintSheet> {
  bool? _color; // null = ще не ініціалізовано з можливостей принтера
  bool _duplex = false;
  int _copies = 1;
  final _pagesController = TextEditingController();

  PrintSource? _source;
  final Map<int, ui.Image> _previews = {};
  List<ui.Image> _thumbs = []; // превʼю окремих фото колажу (для редактора)
  int _previewIndex = 0;
  LayoutOptions _layout = const LayoutOptions();
  bool _opening = false;
  String? _openError;
  bool _layoutHint = false; // «запам'ятовувати макет?» після повторного однакового макета

  PrintProgress? _progress;
  StreamSubscription<PrintProgress>? _sub;
  PrintCancel? _cancel; // поточний друк; null — нічого скасовувати

  bool get _busy => (_progress != null && !_progress!.finished) || _opening;

  @override
  void initState() {
    super.initState();
    final prefs = widget.settings.printers[widget.printer.id];
    if (prefs != null) {
      _color = prefs.color;
      _duplex = prefs.duplex;
    }
    final path = widget.initialPath;
    if (path != null) _open(path);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _source?.dispose();
    _disposePreviews();
    _disposeThumbs();
    _pagesController.dispose();
    super.dispose();
  }

  /// На Android питаємо, звідки брати: галерея (системний Photo Picker) чи файли. На ПК — одразу файли.
  Future<void> _pick() async {
    if (!Platform.isAndroid) return _pickFile();
    final fromGallery = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Kami.shu),
                title: const Text('Галерея'),
                subtitle: const Text('Фото й зображення'),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined, color: Kami.shu),
                title: const Text('Файли'),
                subtitle: const Text('PDF і зображення з провідника'),
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (fromGallery == null) return;
    if (fromGallery) {
      final List<String> paths;
      try {
        paths = await PlatformBridge.pickImages();
      } catch (e) {
        if (mounted) setState(() => _openError = 'Не вдалося взяти фото з галереї: $e');
        return;
      }
      await _openPaths(paths);
    } else {
      await _pickFile();
    }
  }

  Future<void> _pickFile() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF і зображення',
        extensions: PrintSource.allExtensions,
        mimeTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/bmp'],
      ),
    ]);
    await _openPaths([for (final f in files) f.path]);
  }

  /// Одне — відкриваємо як є; кілька зображень — розкладаємо на аркуші й даємо відредагувати.
  Future<void> _openPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final images = paths.where((p) => PrintSource.imageExtensions.contains(p.split('.').last.toLowerCase()));
    if (paths.length > 1 && images.length == paths.length) return _openCollage(paths);
    await _open(paths.first);
  }

  Future<void> _openCollage(List<String> paths) async {
    setState(() {
      _opening = true;
      _openError = null;
      _progress = null;
    });
    try {
      final photos = [for (final p in paths) await ImageSource.open(p)];
      final thumbs = [for (final ph in photos) await ph.preview(0, maxSide: 800)];
      final collage = autoArrange([for (final ph in photos) (ph.pageSize(0).width, ph.pageSize(0).height)]);
      if (!mounted) {
        for (final t in thumbs) {
          t.dispose();
        }
        return;
      }
      await _source?.dispose();
      _disposePreviews();
      _disposeThumbs();
      setState(() {
        _source = CollageSource(photos, collage);
        _thumbs = thumbs;
        _pagesController.clear();
      });
      await _editCollage();
    } catch (e) {
      if (mounted) setState(() => _openError = '$e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _editCollage() async {
    final source = _source;
    if (source is! CollageSource) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CollageEditorScreen(
        source: source,
        thumbs: _thumbs,
        printerMargins: widget.printer.capabilities?.margins ?? SheetMargins.zero,
        onAddPhotos: _pickMorePhotos,
      ),
    ));
    source.collage.removeEmptySheets();
    _disposePreviews();
    final preview = await source.preview(0);
    if (!mounted || _source != source) {
      preview.dispose();
      return;
    }
    setState(() {
      _previews[0] = preview;
      _previewIndex = 0;
    });
  }

  /// Для кнопки «Додати фото» в редакторі.
  Future<List<(ImageSource, ui.Image)>> _pickMorePhotos() async {
    final List<String> paths;
    if (Platform.isAndroid) {
      paths = await PlatformBridge.pickImages();
    } else {
      final files = await openFiles(acceptedTypeGroups: const [
        XTypeGroup(label: 'Зображення', extensions: PrintSource.imageExtensions),
      ]);
      paths = [for (final f in files) f.path];
    }
    return [
      for (final p in paths)
        if (PrintSource.imageExtensions.contains(p.split('.').last.toLowerCase()))
          await ImageSource.open(p).then((ph) async => (ph, await ph.preview(0, maxSide: 800))),
    ];
  }

  void _disposeThumbs() {
    for (final t in _thumbs) {
      t.dispose();
    }
    _thumbs = [];
  }

  Future<void> _open(String path) async {
    setState(() {
      _opening = true;
      _openError = null;
      _progress = null;
    });
    try {
      final source = await PrintSource.open(path);
      final preview = await source.preview(0);
      if (!mounted) {
        preview.dispose();
        await source.dispose();
        return;
      }
      await _source?.dispose();
      _disposePreviews();
      _disposeThumbs();
      setState(() {
        _source = source;
        _previews[0] = preview;
        _previewIndex = 0;
        _layout = widget.settings.layoutFor(document: source.isDocument);
        _pagesController.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _openError = '$e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _disposePreviews() {
    for (final img in _previews.values) {
      img.dispose();
    }
    _previews.clear();
  }

  Future<void> _showPage(int index) async {
    setState(() => _previewIndex = index);
    final source = _source;
    if (source == null || _previews.containsKey(index)) return;
    try {
      final img = await source.preview(index);
      if (!mounted || _source != source) {
        img.dispose();
        return;
      }
      setState(() => _previews[index] = img);
    } catch (_) {}
  }

  List<int>? get _selectedPages {
    final s = _source;
    if (s == null) return null;
    return parsePageRange(_pagesController.text, s.pageCount);
  }

  void _start(Stream<PrintProgress> Function(PrintCancel cancel) print) {
    final cancel = _cancel = PrintCancel();
    final stream = print(cancel);
    setState(() => _progress = const PrintProgress(PrintStage.preparing, 'Готуюсь…'));
    _sub?.cancel();
    _sub = stream.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  /// Запам'ятовує принтер і налаштування, з якими щойно почали друк.
  void _remember({bool withLayout = true}) {
    final o = _options();
    widget.settings.remember(
      printerId: widget.printer.id,
      prefs: PrinterPrefs(color: _color ?? o.color, duplex: _duplex),
      document: _source?.isDocument ?? true,
      layout: withLayout && _source != null && _source is! CollageSource ? _layout : null,
    );
    final document = _source?.isDocument ?? true;
    if (withLayout && widget.settings.shouldHintLayout(document: document)) {
      widget.settings.layoutHintShown = true;
      widget.settings.save();
      setState(() => _layoutHint = true);
    }
  }

  void _answerLayoutHint(bool enable) {
    if (enable) {
      widget.settings.rememberLayout = true;
      widget.settings.save();
    }
    setState(() => _layoutHint = false);
  }

  PrintOptions _options() {
    final caps = widget.printer.capabilities!;
    return PrintOptions(
      color: caps.supportsColor && (_color ?? caps.supportsColor),
      duplex: _duplex,
      copies: _copies,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.discovery,
      builder: (context, _) {
        final theme = Theme.of(context);
        final p = widget.printer;
        final caps = p.capabilities;
        _color ??= caps?.supportsColor;
        final source = _source;
        final pages = _selectedPages;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name, style: theme.textTheme.titleMedium),
              Text([if (caps != null && caps.model != p.name) caps.model, p.host].join(' · '),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              if (caps == null) ...[
                if (p.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Отримую можливості принтера…')),
                  )
                else ...[
                  Text(p.error ?? 'Можливості принтера невідомі',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Kami.shu)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => widget.discovery.refreshCapabilities(p),
                    child: const Text('Спробувати ще раз'),
                  ),
                ],
              ] else ...[
                _FileCard(
                  source: source,
                  preview: _previews[0],
                  opening: _opening,
                  error: _openError,
                  onPick: _busy ? null : _pick,
                ),
                if (source is CollageSource) ...[
                  const SizedBox(height: 16),
                  _CollageCard(
                    source: source,
                    image: _previews[_previewIndex],
                    index: _previewIndex,
                    printerMargins: caps.margins,
                    onIndexChanged: _showPage,
                    onEdit: _busy ? null : _editCollage,
                  ),
                ] else if (source != null) ...[
                  const SizedBox(height: 16),
                  LayoutEditor(
                    source: source,
                    image: _previews[_previewIndex],
                    index: _previewIndex,
                    layout: _layout,
                    printerMargins: caps.margins,
                    canBorderless: caps.supportsBorderless,
                    enabled: !_busy,
                    onChanged: (l) => setState(() => _layout = l),
                    onIndexChanged: _showPage,
                  ),
                ],
                if (source != null && source.pageCount > 1) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pagesController,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Сторінки',
                      hintText: 'усі ${source.pageCount}, або напр. 1-3, 5',
                      errorText: pages == null ? 'Номери від 1 до ${source.pageCount}' : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Колір'),
                  subtitle: caps.supportsColor ? null : const Text('Цей принтер друкує лише чорно-біле'),
                  value: caps.supportsColor && (_color ?? false),
                  onChanged: caps.supportsColor && !_busy ? (v) => setState(() => _color = v) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Двосторонній друк'),
                  subtitle: caps.supportsDuplex ? null : const Text('Не підтримується'),
                  value: caps.supportsDuplex && _duplex,
                  onChanged: caps.supportsDuplex && !_busy ? (v) => setState(() => _duplex = v) : null,
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Копії')),
                    IconButton(
                      onPressed: _copies > 1 && !_busy ? () => setState(() => _copies--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text('$_copies', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      onPressed: _copies < caps.maxCopies.clamp(1, 99) && !_busy ? () => setState(() => _copies++) : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || !caps.supportsUrf || source == null || pages == null
                      ? null
                      : () {
                          _remember();
                          final layout = source is CollageSource ? CollageSource.layout : _layout;
                          _start((c) => printDocument(p, source, _options(), pages: pages, layout: layout, cancel: c));
                        },
                  icon: const Icon(Icons.print),
                  label: Text(source == null
                      ? 'Спершу вибери файл'
                      : 'Друкувати ${pages == null ? '' : _pagesLabel(pages.length)}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
                TextButton(
                  onPressed: _busy || !caps.supportsUrf
                      ? null
                      : () {
                          _remember(withLayout: false);
                          _start((c) => printTestPage(p, _options(), cancel: c));
                        },
                  style: TextButton.styleFrom(foregroundColor: Kami.stone),
                  child: const Text('Тестова сторінка'),
                ),
                if (!caps.supportsUrf)
                  Text('Принтер не підтримує AirPrint-растр', style: theme.textTheme.bodySmall),
                if (_layoutHint) _LayoutHint(onAnswer: _answerLayoutHint),
                if (_progress != null) ...[
                  const SizedBox(height: 8),
                  _ProgressView(progress: _progress!),
                  if (!_progress!.finished)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _cancel == null || _cancel!.isCancelled
                            ? null
                            : () => setState(() => _cancel!.cancel()),
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(_cancel?.isCancelled ?? false ? 'Скасовую…' : 'Скасувати'),
                        style: TextButton.styleFrom(foregroundColor: Kami.shu),
                      ),
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  static String _pagesLabel(int n) {
    final mod10 = n % 10, mod100 = n % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'сторінку'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? 'сторінки' : 'сторінок');
    return '$n $word';
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.source,
    required this.preview,
    required this.opening,
    required this.error,
    required this.onPick,
  });

  final PrintSource? source;
  final ui.Image? preview;
  final bool opening;
  final String? error;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = source;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Превʼю першої сторінки у пропорціях A4.
              Container(
                width: 56,
                height: 79,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Kami.line),
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.center,
                child: opening
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Kami.stone))
                    : preview != null
                        ? RawImage(image: preview, fit: BoxFit.contain)
                        : const Icon(Icons.note_add_outlined, color: Kami.stone),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s?.name ?? (opening ? 'Відкриваю…' : 'Вибрати файл'),
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      error ?? (s != null ? '${s.pageCount} стор. · натисни, щоб змінити' : 'PDF або зображення'),
                      style: theme.textTheme.bodySmall?.copyWith(color: error != null ? Kami.shu : null),
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
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.progress});

  final PrintProgress progress;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final (icon, color) = switch (progress.stage) {
      PrintStage.done => (Icons.check_circle, Kami.matcha),
      PrintStage.failed => (Icons.error_outline, Kami.shu),
      PrintStage.cancelled => (Icons.block, Kami.stone),
      _ => (null, Kami.stone),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon == null)
          LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 2,
            color: Kami.shu,
            backgroundColor: Kami.line,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (icon != null) ...[Icon(icon, color: color, size: 20), const SizedBox(width: 8)],
            Expanded(child: Text(progress.message, style: style?.copyWith(color: icon != null ? color : null))),
          ],
        ),
      ],
    );
  }
}

/// Ненав'язлива підказка: людина вдруге вручну виставила той самий макет.
class _LayoutHint extends StatelessWidget {
  const _LayoutHint({required this.onAnswer});

  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      decoration: BoxDecoration(
        color: Kami.shu.withValues(alpha: 0.06),
        border: Border.all(color: Kami.shu.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ти вже вдруге ставиш той самий макет. Запам\'ятовувати його, щоб наступного разу '
              'він був одразу? Це можна змінити в налаштуваннях.',
              style: theme.textTheme.bodySmall),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => onAnswer(false),
                style: TextButton.styleFrom(foregroundColor: Kami.stone),
                child: const Text('Ні'),
              ),
              TextButton(
                onPressed: () => onAnswer(true),
                style: TextButton.styleFrom(foregroundColor: Kami.shu),
                child: const Text('Увімкнути'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Колаж в аркуші друку: превʼю аркушів 1:1 і кнопка назад у редактор.
class _CollageCard extends StatelessWidget {
  const _CollageCard({
    required this.source,
    required this.image,
    required this.index,
    required this.printerMargins,
    required this.onIndexChanged,
    required this.onEdit,
  });

  final CollageSource source;
  final ui.Image? image;
  final int index;
  final SheetMargins printerMargins;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 260,
          child: SheetPreview(
            size: source.pageSize(index),
            image: image,
            layout: CollageSource.layout,
            printerMargins: printerMargins,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (source.pageCount > 1) ...[
              IconButton(
                onPressed: index > 0 ? () => onIndexChanged(index - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Аркуш ${index + 1} з ${source.pageCount}', style: label),
              IconButton(
                onPressed: index < source.pageCount - 1 ? () => onIndexChanged(index + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Редагувати аркуші'),
            ),
          ],
        ),
      ],
    );
  }
}
