// Кодувальник AirPrint-растру (image/urf, «UNIRAST»).
// Формат: "UNIRAST\0" + кількість сторінок (u32 BE), далі для кожної сторінки
// 32-байтний заголовок і рядки, стиснуті модифікованим PackBits (як у PWG-raster).
import 'dart:typed_data';

enum SheetBack { normal, flipped, rotated, manualTumble }

enum UrfDuplex {
  none(1),
  shortEdge(2),
  longEdge(3);

  final int code;
  const UrfDuplex(this.code);
}

/// Сторінка растру: або 8-бітний сірий (1 байт/піксель), або sRGB (3 байти/піксель).
class UrfPage {
  final int width, height, dpi;
  final bool color;
  final Uint8List pixels;

  UrfPage({required this.width, required this.height, required this.dpi, required this.color, required this.pixels})
      : assert(pixels.length == width * height * (color ? 3 : 1));

  int get bytesPerPixel => color ? 3 : 1;

  /// З RGBA (як дає Flutter `Image.toByteData(rawRgba)`), фон вважається непрозорим.
  factory UrfPage.fromRgba(Uint8List rgba, int width, int height, int dpi, {required bool color}) {
    final n = width * height;
    final out = Uint8List(n * (color ? 3 : 1));
    if (color) {
      for (var i = 0, j = 0; i < n; i++, j += 3) {
        out[j] = rgba[i * 4];
        out[j + 1] = rgba[i * 4 + 1];
        out[j + 2] = rgba[i * 4 + 2];
      }
    } else {
      for (var i = 0; i < n; i++) {
        final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
        out[i] = (r * 299 + g * 587 + b * 114 + 500) ~/ 1000;
      }
    }
    return UrfPage(width: width, height: height, dpi: dpi, color: color, pixels: out);
  }

  /// Перетворення зворотного боку аркуша при дуплексі (як у libcupsfilters).
  UrfPage forBackSide(SheetBack sheetBack, {required bool tumble}) {
    switch (sheetBack) {
      case SheetBack.normal:
        return this;
      case SheetBack.flipped:
        return tumble ? _mirrored(horizontal: true) : _mirrored(horizontal: false);
      case SheetBack.rotated:
        return tumble ? this : _rotated180();
      case SheetBack.manualTumble:
        return tumble ? _rotated180() : this;
    }
  }

  UrfPage _rotated180() {
    final bpp = bytesPerPixel;
    final n = width * height;
    final out = Uint8List(pixels.length);
    for (var i = 0; i < n; i++) {
      final src = i * bpp, dst = (n - 1 - i) * bpp;
      for (var k = 0; k < bpp; k++) {
        out[dst + k] = pixels[src + k];
      }
    }
    return UrfPage(width: width, height: height, dpi: dpi, color: color, pixels: out);
  }

  UrfPage _mirrored({required bool horizontal}) {
    final bpp = bytesPerPixel;
    final stride = width * bpp;
    final out = Uint8List(pixels.length);
    for (var y = 0; y < height; y++) {
      if (horizontal) {
        for (var x = 0; x < width; x++) {
          final src = y * stride + x * bpp, dst = y * stride + (width - 1 - x) * bpp;
          for (var k = 0; k < bpp; k++) {
            out[dst + k] = pixels[src + k];
          }
        }
      } else {
        out.setRange((height - 1 - y) * stride, (height - y) * stride, pixels, y * stride);
      }
    }
    return UrfPage(width: width, height: height, dpi: dpi, color: color, pixels: out);
  }
}

/// Простий буфер, що росте, — швидший за BytesBuilder при побайтовому записі.
class _Out {
  Uint8List _buf = Uint8List(1 << 16);
  int length = 0;

  void _ensure(int extra) {
    if (length + extra <= _buf.length) return;
    var cap = _buf.length * 2;
    while (cap < length + extra) {
      cap *= 2;
    }
    _buf = Uint8List(cap)..setRange(0, length, _buf);
  }

  void byte(int b) {
    _ensure(1);
    _buf[length++] = b;
  }

  void bytes(Uint8List src, int start, int count) {
    _ensure(count);
    _buf.setRange(length, length + count, src, start);
    length += count;
  }

  Uint8List take() => _buf.sublist(0, length);
}

bool _pixelEq(Uint8List p, int a, int b, int bpp) {
  for (var k = 0; k < bpp; k++) {
    if (p[a + k] != p[b + k]) return false;
  }
  return true;
}

bool _rowEq(Uint8List p, int a, int b, int stride) {
  for (var k = 0; k < stride; k++) {
    if (p[a + k] != p[b + k]) return false;
  }
  return true;
}

/// Найдовша літеральна серія. Формат дозволяє 128 (так робить і CUPS), але Xerox WorkCentre 3225
/// (прошивка SPL 5.90) одного разу видав «URFPWG Decoding Fail» на фото — страхуємося коротшими
/// серіями. Коштує ~1–2 % розміру файлу.
const _maxLiteral = 64;

void _encodeRow(Uint8List px, int start, int width, int bpp, _Out out) {
  var x = 0;
  while (x < width) {
    // серія однакових пікселів
    var run = 1;
    while (x + run < width && run < 128 && _pixelEq(px, start + x * bpp, start + (x + run) * bpp, bpp)) {
      run++;
    }
    if (run > 1) {
      out.byte(run - 1);
      out.bytes(px, start + x * bpp, bpp);
      x += run;
      continue;
    }
    // літерали: до початку наступної серії
    var lit = 1;
    while (x + lit < width && lit < _maxLiteral) {
      if (x + lit + 1 < width && _pixelEq(px, start + (x + lit) * bpp, start + (x + lit + 1) * bpp, bpp)) break;
      lit++;
    }
    out.byte(lit == 1 ? 0 : 257 - lit);
    out.bytes(px, start + x * bpp, lit * bpp);
    x += lit;
  }
}

void _encodePage(UrfPage page, UrfDuplex duplex, _Out out) {
  final header = Uint8List(32);
  final hd = header.buffer.asByteData();
  header[0] = page.color ? 24 : 8;
  header[1] = page.color ? 1 : 0; // 1 = sRGB, 0 = sGray
  header[2] = duplex.code;
  header[3] = 0; // якість: за замовчуванням принтера
  hd.setUint32(12, page.width);
  hd.setUint32(16, page.height);
  hd.setUint32(20, page.dpi);
  out.bytes(header, 0, 32);

  final bpp = page.bytesPerPixel;
  final stride = page.width * bpp;
  final px = page.pixels;
  var y = 0;
  while (y < page.height) {
    final rowStart = y * stride;
    var repeat = 1;
    while (y + repeat < page.height && repeat < 256 && _rowEq(px, rowStart, (y + repeat) * stride, stride)) {
      repeat++;
    }
    out.byte(repeat - 1);
    _encodeRow(px, rowStart, page.width, bpp, out);
    y += repeat;
  }
}

/// Заголовок URF-файлу: "UNIRAST\0" + кількість сторінок.
Uint8List urfFileHeader(int pageCount) {
  final h = Uint8List(12)..setRange(0, 7, 'UNIRAST'.codeUnits);
  h.buffer.asByteData().setUint32(8, pageCount);
  return h;
}

/// Кодує одну сторінку (заголовок сторінки + рядки). Потрібна для потокового друку великих документів.
Uint8List encodeUrfPage(UrfPage page, {UrfDuplex duplex = UrfDuplex.none}) {
  final out = _Out();
  _encodePage(page, duplex, out);
  return out.take();
}

/// Кодує документ з кількох сторінок у повний URF-файл.
Uint8List encodeUrf(List<UrfPage> pages, {UrfDuplex duplex = UrfDuplex.none}) {
  final out = _Out();
  out.bytes(urfFileHeader(pages.length), 0, 12);
  for (final p in pages) {
    _encodePage(p, duplex, out);
  }
  return out.take();
}

/// Декодер — для тестів і налагодження.
List<UrfPage> decodeUrf(Uint8List data) {
  if (String.fromCharCodes(data.sublist(0, 7)) != 'UNIRAST') {
    throw const FormatException('Не URF');
  }
  final bd = ByteData.sublistView(data);
  final count = bd.getUint32(8);
  var pos = 12;
  final pages = <UrfPage>[];
  for (var p = 0; p < count; p++) {
    final bpp = data[pos] ~/ 8;
    final color = data[pos + 1] == 1;
    final w = bd.getUint32(pos + 12), h = bd.getUint32(pos + 16), dpi = bd.getUint32(pos + 20);
    pos += 32;
    final stride = w * bpp;
    final px = Uint8List(stride * h);
    var row = 0;
    while (row < h) {
      final rep = data[pos++] + 1;
      final line = Uint8List(stride);
      var filled = 0;
      while (filled < stride) {
        final c = data[pos++];
        if (c == 128) {
          line.fillRange(filled, stride, 0xff);
          filled = stride;
        } else if (c > 128) {
          final n = (257 - c) * bpp;
          line.setRange(filled, filled + n, data, pos);
          pos += n;
          filled += n;
        } else {
          for (var i = 0; i <= c; i++) {
            line.setRange(filled, filled + bpp, data, pos);
            filled += bpp;
          }
          pos += bpp;
        }
      }
      for (var r = 0; r < rep; r++) {
        px.setRange((row + r) * stride, (row + r + 1) * stride, line);
      }
      row += rep;
    }
    pages.add(UrfPage(width: w, height: h, dpi: dpi, color: color, pixels: px));
  }
  return pages;
}
