// Джерела для друку: PDF, зображення, тестова сторінка. Кожне вміє відрендерити
// сторінку, вписану в аркуш A4 з потрібною роздільністю.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'compose.dart';
import 'test_page.dart';

class SourceException implements Exception {
  final String message;
  SourceException(this.message);
  @override
  String toString() => message;
}

abstract class PrintSource {
  String get name;
  int get pageCount;

  /// true для документів (PDF), false для фото — від цього залежать доступні варіанти макета.
  bool get isDocument;

  /// Пропорції (і, якщо відомо, фізичний розмір) сторінки [index].
  ContentSize pageSize(int index);

  /// Рендерить сторінку [index] (з нуля) рівно в [width]×[height] пікселів.
  Future<SourcePixels> render(int index, {required int width, required int height});

  Future<void> dispose() async {}

  /// Маленьке превʼю сторінки для інтерфейсу.
  Future<ui.Image> preview(int index, {int maxSide = 480}) async {
    final size = pageSize(index);
    final k = maxSide / (size.width > size.height ? size.width : size.height);
    final px = await render(
      index,
      width: (size.width * k).round().clamp(1, maxSide),
      height: (size.height * k).round().clamp(1, maxSide),
    );
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      px.data,
      px.width,
      px.height,
      px.order == PixelOrder.rgba ? ui.PixelFormat.rgba8888 : ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  static const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
  static const allExtensions = ['pdf', ...imageExtensions];

  static Future<PrintSource> open(String path) async {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    if (ext == 'pdf') return PdfSource.open(path);
    if (imageExtensions.contains(ext)) return ImageSource.open(path);
    throw SourceException('Формат «.$ext» поки не підтримується. Можна PDF або зображення.');
  }
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

class PdfSource extends PrintSource {
  PdfSource._(this._doc, this.name);

  final PdfDocument _doc;
  @override
  final String name;

  static Future<PdfSource> open(String path) async {
    try {
      final doc = await PdfDocument.openFile(path);
      return PdfSource._(doc, _basename(path));
    } catch (e) {
      throw SourceException('Не вдалося відкрити PDF: $e');
    }
  }

  @override
  int get pageCount => _doc.pages.length;

  @override
  bool get isDocument => true;

  @override
  ContentSize pageSize(int index) {
    final page = _doc.pages[index];
    const mmPerPt = 25.4 / 72;
    return ContentSize(page.width, page.height, widthMm: page.width * mmPerPt, heightMm: page.height * mmPerPt);
  }

  @override
  Future<SourcePixels> render(int index, {required int width, required int height}) async {
    final page = _doc.pages[index];
    final img = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (img == null) throw SourceException('Не вдалося відрендерити сторінку ${index + 1}');
    try {
      return SourcePixels(
        data: Uint8List.fromList(img.pixels), // копія: пам'ять PdfImage звільняється в dispose()
        width: img.width,
        height: img.height,
        order: PixelOrder.bgra,
      );
    } finally {
      img.dispose();
    }
  }

  @override
  Future<void> dispose() => _doc.dispose();
}

class ImageSource extends PrintSource {
  ImageSource._(this._bytes, this.name, this._width, this._height);

  final Uint8List _bytes;
  final int _width, _height;
  @override
  final String name;

  static Future<ImageSource> open(String path) async {
    final bytes = await File(path).readAsBytes();
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      descriptor.dispose();
      buffer.dispose();
      return ImageSource._(bytes, _basename(path), w, h);
    } catch (e) {
      throw SourceException('Не вдалося прочитати зображення: $e');
    }
  }

  @override
  int get pageCount => 1;

  @override
  bool get isDocument => false;

  @override
  ContentSize pageSize(int index) => ContentSize(_width.toDouble(), _height.toDouble());

  @override
  Future<SourcePixels> render(int index, {required int width, required int height}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(_bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec(targetWidth: width, targetHeight: height);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      return SourcePixels(
        data: data!.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        order: PixelOrder.rgba,
      );
    } finally {
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

class TestPageSource extends PrintSource {
  TestPageSource({required this.pageCount, required this.color, required this.info});

  @override
  final int pageCount;
  final bool color;
  final String info;

  @override
  String get name => 'KamiDrop test page';

  @override
  bool get isDocument => true;

  @override
  ContentSize pageSize(int index) => const ContentSize(210, 297, widthMm: 210, heightMm: 297);

  @override
  Future<SourcePixels> render(int index, {required int width, required int height}) async {
    final dpi = (width * 25.4 / 210).round();
    final r = await renderTestPage(pageNumber: index + 1, dpi: dpi, color: color, info: info);
    return SourcePixels(data: r.rgba, width: r.width, height: r.height, order: PixelOrder.rgba, premultiplied: true);
  }
}
