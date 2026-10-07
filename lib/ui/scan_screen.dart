import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/platform_bridge.dart';
import '../scan/escl.dart';
import '../scan/pdf_writer.dart';
import '../settings.dart';
import '../theme.dart';

/// A4 у 1/300 дюйма (8,27 × 11,69″).
const _a4Width = 2480, _a4Height = 3508;

class _ScannedPage {
  _ScannedPage(this.pdfPage, this.thumb);
  final PdfImagePage pdfPage;
  final ui.Image thumb;
}

/// У чому віддавати скан. PDF — один файл; JPEG і PNG — файл на сторінку.
enum ScanFormat {
  pdf('PDF', 'pdf', 'application/pdf'),
  jpeg('JPEG', 'jpg', 'image/jpeg'),
  png('PNG', 'png', 'image/png');

  const ScanFormat(this.label, this.ext, this.mime);
  final String label, ext, mime;
}

/// Сканування: скло або подавач, колір / сіре / чорно-біле, роздільність; усі сторінки → один PDF.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.scanner, required this.settings, required this.onPrint});

  final ScannerRef scanner;
  final KamiSettings settings;

  /// «Надрукувати»: віддає шлях до PDF (далі — вибір принтера, як для файлу з «Поділитися»).
  final void Function(String pdfPath) onPrint;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late ScanColor _color;
  late int _dpi;
  late bool _feeder; // подавач замість скла
  late ScanFormat _format;
  final _pages = <_ScannedPage>[];
  bool _scanning = false;
  int _gotPages = 0; // скільки сторінок уже прийшло в поточному скануванні (подавач)
  String? _message; // помилка або «Збережено …»
  bool _messageIsError = false;

  ScannerCaps get _caps => widget.scanner.caps;

  List<ScanColor> get _colors => [
        if (_caps.colorModes.contains('RGB24')) ScanColor.color,
        if (_caps.colorModes.contains('Grayscale8')) ...[ScanColor.gray, ScanColor.blackWhite],
      ];

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _color = _colors.firstWhere((c) => c.name == s.scanColor, orElse: () => _colors.first);
    final res = _caps.resolutions;
    final want = s.scanDpi ?? 200;
    _dpi = res.isEmpty ? want : res.reduce((a, b) => (a - want).abs() <= (b - want).abs() ? a : b);
    _feeder = _caps.adf && (!_caps.platen || s.scanFeeder == true);
    _format = ScanFormat.values.firstWhere((f) => f.name == s.scanFormat, orElse: () => ScanFormat.pdf);
  }

  @override
  void dispose() {
    for (final p in _pages) {
      p.thumb.dispose();
    }
    super.dispose();
  }

  void _say(String text, {bool error = false}) => setState(() {
        _message = text;
        _messageIsError = error;
      });

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _gotPages = 0;
      _message = null;
    });
    widget.settings
      ..scanColor = _color.name
      ..scanDpi = _dpi
      ..scanFeeder = _feeder
      ..save();
    try {
      final xml = scanSettingsXml(
        // Чорно-біле скануємо сірим і робимо поріг самі: JPEG однобітним не буває.
        colorMode: _color == ScanColor.blackWhite ? ScanColor.gray.escl : _color.escl,
        dpi: _dpi,
        widthUnits: _a4Width.clamp(1, _caps.maxWidth),
        heightUnits: _a4Height.clamp(1, _caps.maxHeight),
        source: _feeder ? 'Feeder' : 'Platen',
      );
      final jpegs = await widget.scanner.client.scan(xml, onPage: (n) {
        if (mounted) setState(() => _gotPages = n);
      });
      for (final jpeg in jpegs) {
        final page = await _toPage(jpeg);
        if (!mounted) return page.thumb.dispose();
        setState(() => _pages.add(page));
      }
    } catch (e) {
      if (mounted) _say('$e', error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<_ScannedPage> _toPage(Uint8List jpeg) async {
    final info = jpegInfo(jpeg);
    if (info == null) throw ScanException('Сканер віддав не JPEG');
    final (w, h, comps) = info;
    if (_color != ScanColor.blackWhite) {
      return _ScannedPage(JpegPage(jpeg, w, h, _dpi, components: comps), await _decode(jpeg, targetWidth: 360));
    }
    // Чорно-біле: повний розмір → сірий → поріг (в ізоляті, бо це мільйони пікселів).
    // Мініатюра — з уже чорно-білого, щоб було видно саме те, що піде в PDF.
    final full = await _decode(jpeg);
    final rgba = (await full.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    full.dispose();
    final (bits, thumbRgba, tw, th) = await Isolate.run(() => _rgbaToBilevel(rgba, w, h, 360));
    return _ScannedPage(BilevelPage(bits, w, h, _dpi), await _fromRgba(thumbRgba, tw, th));
  }

  static Future<ui.Image> _decode(Uint8List bytes, {int? targetWidth}) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<ui.Image> _fromRgba(Uint8List rgba, int w, int h) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  Future<Directory> _freshDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/scans');
    if (await dir.exists()) await dir.delete(recursive: true);
    return dir.create(recursive: true);
  }

  /// Збирає PDF у кеші (cache/scans) і повертає файл.
  Future<File> _writePdf() async {
    final pages = [for (final p in _pages) p.pdfPage];
    final name = _fileName();
    final pdf = await Isolate.run(() => buildPdf(pages, title: name));
    final dir = await _freshDir();
    return File('${dir.path}/$name.pdf')..writeAsBytesSync(pdf);
  }

  /// Файли у вибраному форматі (cache/scans). JPEG — байти сканера як є; чорно-біла сторінка
  /// в JPEG не має сенсу (він не буває 1-бітним), тож вона йде як PNG.
  Future<List<File>> _writeFiles() async {
    if (_format == ScanFormat.pdf) return [await _writePdf()];
    final name = _fileName();
    final dir = await _freshDir();
    final files = <File>[];
    for (var i = 0; i < _pages.length; i++) {
      final page = _pages[i].pdfPage;
      final asJpeg = _format == ScanFormat.jpeg && page is JpegPage;
      final bytes = asJpeg ? page.jpeg : await _toPng(page);
      final suffix = _pages.length == 1 ? '' : ' - ${i + 1}';
      files.add(File('${dir.path}/$name$suffix.${asJpeg ? 'jpg' : 'png'}')..writeAsBytesSync(bytes));
    }
    return files;
  }

  /// Сторінка → PNG системним кодеком (без втрат).
  static Future<Uint8List> _toPng(PdfImagePage page) async {
    final ui.Image image;
    switch (page) {
      case JpegPage():
        image = await _decode(page.jpeg);
      case BilevelPage():
        final rgba = await Isolate.run(() => _bilevelToRgba(page.bits, page.width, page.height));
        image = await _fromRgba(rgba, page.width, page.height);
    }
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  String _fileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Скан ${two(n.day)}.${two(n.month)}.${n.year} ${two(n.hour)}-${two(n.minute)}';
  }

  /// MIME для «Поділитися»: якщо файли різні (JPEG + PNG для ч/б) — загальний image/*.
  static String _mimeOf(List<File> files) {
    final exts = files.map((f) => f.path.split('.').last).toSet();
    if (exts.length > 1) return 'image/*';
    return switch (exts.single) { 'pdf' => 'application/pdf', 'jpg' => 'image/jpeg', _ => 'image/png' };
  }

  Future<void> _share() async {
    try {
      final files = await _writeFiles();
      await PlatformBridge.shareFiles([for (final f in files) f.path], _mimeOf(files));
    } catch (e) {
      _say('Не вдалося поділитися: $e', error: true);
    }
  }

  Future<void> _save() async {
    try {
      final files = await _writeFiles();
      String? where;
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final mime = _mimeOf([f]);
        where = await PlatformBridge.saveToDownloads(f.path, name, mime);
        if (where == null) break;
      }
      if (where == null) {
        _say('Зберегти не вийшло — скористайся «Поділитися»', error: true);
      } else {
        final folder = where.substring(0, where.lastIndexOf('/'));
        final bw = _format == ScanFormat.jpeg && _pages.any((p) => p.pdfPage is BilevelPage)
            ? ' (чорно-білі сторінки — у PNG)'
            : '';
        _say(files.length == 1
            ? 'Збережено: $where'
            : 'Збережено ${files.length} ${_filesWord(files.length)} у $folder$bw');
      }
    } catch (e) {
      _say('Не вдалося зберегти: $e', error: true);
    }
  }

  Future<void> _print() async {
    try {
      final f = await _writePdf();
      widget.onPrint(f.path);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final has = _pages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('Сканування · ${_shortName(widget.scanner.name)}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (!has)
              Container(
                height: 220,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(border: Border.all(color: Kami.line), borderRadius: BorderRadius.circular(10)),
                child: Text(
                    _feeder
                        ? 'Поклади аркуші в подавач\nі натисни «Сканувати» — відскануються всі'
                        : 'Поклади аркуш на скло лицем донизу\nі натисни «Сканувати»',
                    textAlign: TextAlign.center,
                    style: small),
              )
            else
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Kami.line), color: Colors.white),
                        child: RawImage(image: _pages[i].thumb, height: 218, fit: BoxFit.contain),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Text('${i + 1}', style: theme.textTheme.labelLarge?.copyWith(color: Kami.stone)),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          tooltip: 'Прибрати сторінку',
                          icon: const Icon(Icons.close, size: 18, color: Kami.stone),
                          onPressed: _scanning ? null : () => setState(() => _pages.removeAt(i).thumb.dispose()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (_caps.adf && _caps.platen) ...[
              Text('Звідки', style: small),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Скло')),
                  ButtonSegment(value: true, label: Text('Подавач')),
                ],
                selected: {_feeder},
                onSelectionChanged: _scanning ? null : (s) => setState(() => _feeder = s.first),
              ),
              const SizedBox(height: 14),
            ],
            Text('Колір', style: small),
            const SizedBox(height: 6),
            SegmentedButton<ScanColor>(
              showSelectedIcon: false,
              segments: [
                for (final c in _colors)
                  ButtonSegment(
                    value: c,
                    label: Text(switch (c) {
                      ScanColor.color => 'Кольорове',
                      ScanColor.gray => 'Сіре',
                      ScanColor.blackWhite => 'Чорно-біле',
                    }),
                  ),
              ],
              selected: {_color},
              onSelectionChanged: _scanning ? null : (s) => setState(() => _color = s.first),
            ),
            const SizedBox(height: 14),
            Text('Роздільність', style: small),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final r in _caps.resolutions)
                  ChoiceChip(
                    label: Text('$r dpi'),
                    selected: _dpi == r,
                    showCheckmark: false,
                    selectedColor: Kami.shu.withValues(alpha: 0.15),
                    onSelected: _scanning ? null : (_) => setState(() => _dpi = r),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                [
                  '200 dpi — документи',
                  if (_caps.resolutions.contains(300)) '300 — фото',
                  if (_caps.resolutions.contains(600)) '600 — дрібні деталі (довго й великий файл)',
                ].join(', '),
                style: small?.copyWith(color: Kami.stone)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_scanning
                  ? (_gotPages > 0 ? 'Сканую… $_gotPages стор.' : 'Сканую…')
                  : (has ? (_feeder ? 'Сканувати ще' : 'Сканувати ще сторінку') : 'Сканувати')),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: small?.copyWith(color: _messageIsError ? Kami.shu : Kami.matcha)),
            ],
            if (has) ...[
              const SizedBox(height: 16),
              Text('Формат', style: small),
              const SizedBox(height: 6),
              SegmentedButton<ScanFormat>(
                showSelectedIcon: false,
                segments: [for (final f in ScanFormat.values) ButtonSegment(value: f, label: Text(f.label))],
                selected: {_format},
                onSelectionChanged: (s) {
                  setState(() => _format = s.first);
                  widget.settings
                    ..scanFormat = _format.name
                    ..save();
                },
              ),
              const SizedBox(height: 6),
              Text(
                  _format == ScanFormat.pdf
                      ? '${_pages.length} стор. → один PDF'
                      : '${_pages.length} стор. → ${_pages.length} ${_format.label}-${_filesWord(_pages.length)}',
                  style: small,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (Platform.isAndroid) ...[
                    OutlinedButton.icon(
                      onPressed: _scanning ? null : _share,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Поділитися'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _scanning ? null : _save,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Зберегти'),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _scanning ? null : _print,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Друк'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// RGBA → сірий → 1 біт, плюс зменшене до [thumbWidth] RGBA-превʼю з цих бітів.
/// Top-level, щоб Isolate.run не тягнув зайвого.
(Uint8List, Uint8List, int, int) _rgbaToBilevel(Uint8List rgba, int w, int h, int thumbWidth) {
  final gray = Uint8List(w * h);
  for (var i = 0, j = 0; i < gray.length; i++, j += 4) {
    gray[i] = (rgba[j] * 299 + rgba[j + 1] * 587 + rgba[j + 2] * 114) ~/ 1000;
  }
  final bits = toBilevel(gray, w, h);
  final stride = (w + 7) >> 3;
  final tw = thumbWidth, th = (h * thumbWidth / w).round();
  final thumb = Uint8List(tw * th * 4);
  // Піксель мініатюри чорний, якщо в його області є хоч одна чорна точка — інакше тонкі лінії зникають.
  for (var y = 0; y < th; y++) {
    final y0 = y * h ~/ th, y1 = ((y + 1) * h ~/ th).clamp(y0 + 1, h);
    for (var x = 0; x < tw; x++) {
      final x0 = x * w ~/ tw, x1 = ((x + 1) * w ~/ tw).clamp(x0 + 1, w);
      var black = false;
      for (var sy = y0; sy < y1 && !black; sy++) {
        for (var sx = x0; sx < x1; sx++) {
          if (bits[sy * stride + (sx >> 3)] & (0x80 >> (sx & 7)) == 0) {
            black = true;
            break;
          }
        }
      }
      final o = (y * tw + x) * 4;
      thumb[o] = thumb[o + 1] = thumb[o + 2] = black ? 0 : 255;
      thumb[o + 3] = 255;
    }
  }
  return (bits, thumb, tw, th);
}

/// «WSD Xerox WorkCentre 3225 (XRX000000000000)» → «Xerox WorkCentre 3225».
String _shortName(String name) =>
    name.replaceFirst(RegExp(r'^\s*WSD\s+'), '').replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();

/// 1 біт → RGBA (білий/чорний) для кодування в PNG. Top-level для Isolate.run.
Uint8List _bilevelToRgba(Uint8List bits, int w, int h) {
  final stride = (w + 7) >> 3;
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = bits[y * stride + (x >> 3)] & (0x80 >> (x & 7)) != 0 ? 255 : 0;
      final o = (y * w + x) * 4;
      out[o] = out[o + 1] = out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return out;
}

/// 1 файл, 2 файли, 5 файлів, 21 файл.
String _filesWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'файл';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'файли';
  return 'файлів';
}
