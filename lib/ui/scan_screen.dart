import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../discovery/discovery.dart';
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

/// Сканування зі скла: колір / сіре / чорно-біле, роздільність; кілька сторінок → один PDF.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.printer, required this.settings, required this.onPrint});

  final DiscoveredPrinter printer;
  final KamiSettings settings;

  /// «Надрукувати»: віддає шлях до PDF (далі — вибір принтера, як для файлу з «Поділитися»).
  final void Function(String pdfPath) onPrint;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late ScanColor _color;
  late int _dpi;
  final _pages = <_ScannedPage>[];
  bool _scanning = false;
  String? _message; // помилка або «Збережено …»
  bool _messageIsError = false;

  ScannerCaps get _caps => widget.printer.scanner!;

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
      _message = null;
    });
    widget.settings
      ..scanColor = _color.name
      ..scanDpi = _dpi
      ..save();
    try {
      final xml = scanSettingsXml(
        // Чорно-біле скануємо сірим і робимо поріг самі: JPEG однобітним не буває.
        colorMode: _color == ScanColor.blackWhite ? ScanColor.gray.escl : _color.escl,
        dpi: _dpi,
        widthUnits: _a4Width.clamp(1, _caps.maxWidth),
        heightUnits: _a4Height.clamp(1, _caps.maxHeight),
      );
      final jpeg = await EsclClient(host: widget.printer.host).scanPage(xml);
      final page = await _toPage(jpeg);
      if (!mounted) return page.thumb.dispose();
      setState(() => _pages.add(page));
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

  /// Збирає PDF у кеші (cache/scans) і повертає шлях.
  Future<File> _writePdf() async {
    final pages = [for (final p in _pages) p.pdfPage];
    final name = _fileName();
    final pdf = await Isolate.run(() => buildPdf(pages, title: name));
    final dir = Directory('${(await getTemporaryDirectory()).path}/scans');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return File('${dir.path}/$name.pdf')..writeAsBytesSync(pdf);
  }

  String _fileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Скан ${two(n.day)}.${two(n.month)}.${n.year} ${two(n.hour)}-${two(n.minute)}';
  }

  Future<void> _share() async {
    try {
      final f = await _writePdf();
      await PlatformBridge.shareFile(f.path, 'application/pdf');
    } catch (e) {
      _say('Не вдалося поділитися: $e', error: true);
    }
  }

  Future<void> _save() async {
    try {
      final f = await _writePdf();
      final where = await PlatformBridge.saveToDownloads(f.path, f.uri.pathSegments.last, 'application/pdf');
      _say(where == null ? 'Зберегти не вийшло — скористайся «Поділитися»' : 'Збережено: $where',
          error: where == null);
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
      appBar: AppBar(title: Text('Сканування · ${_caps.model}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (!has)
              Container(
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: Kami.line), borderRadius: BorderRadius.circular(10)),
                child: Text('Поклади аркуш на скло лицем донизу\nі натисни «Сканувати»',
                    textAlign: TextAlign.center, style: small),
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
            Text('200 dpi — документи, 300 — фото, 600 — дрібні деталі (довго й великий файл)',
                style: small?.copyWith(color: Kami.stone)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_scanning ? 'Сканую…' : (has ? 'Сканувати ще сторінку' : 'Сканувати')),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: small?.copyWith(color: _messageIsError ? Kami.shu : Kami.matcha)),
            ],
            if (has) ...[
              const SizedBox(height: 16),
              Text('${_pages.length} стор. → PDF', style: small, textAlign: TextAlign.center),
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
