// Мінімальний PDF зі сканів: сторінка = одне зображення на весь аркуш, розмір з dpi.
// Кольорові/сірі — JPEG сканера без перекодування (DCTDecode); чорно-білі — 1 біт (FlateDecode).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

sealed class PdfImagePage {
  const PdfImagePage(this.width, this.height, this.dpi);
  final int width, height, dpi;
}

/// JPEG як є. [components]: 1 — сірий, 3 — RGB.
class JpegPage extends PdfImagePage {
  const JpegPage(this.jpeg, int width, int height, int dpi, {this.components = 3}) : super(width, height, dpi);
  final Uint8List jpeg;
  final int components;
}

/// 1 біт на піксель, рядки вирівняні до байта, 1 — білий, 0 — чорний (як DeviceGray).
class BilevelPage extends PdfImagePage {
  const BilevelPage(this.bits, int width, int height, int dpi) : super(width, height, dpi);
  final Uint8List bits;
}

/// Розмір і кількість каналів JPEG із маркера SOF. null — не JPEG.
(int width, int height, int components)? jpegInfo(Uint8List d) {
  if (d.length < 4 || d[0] != 0xFF || d[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < d.length) {
    if (d[i] != 0xFF) return null;
    final marker = d[i + 1];
    final len = d[i + 2] << 8 | d[i + 3];
    // SOF0..SOF15, крім DHT (C4), JPG (C8), DAC (CC).
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      final h = d[i + 5] << 8 | d[i + 6], w = d[i + 7] << 8 | d[i + 8];
      return (w, h, d[i + 9]);
    }
    i += 2 + len;
  }
  return null;
}

/// Сірий (1 байт на піксель) → 1 біт за порогом [threshold].
Uint8List toBilevel(Uint8List gray, int width, int height, {int threshold = 160}) {
  final stride = (width + 7) >> 3;
  final out = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (gray[y * width + x] >= threshold) out[y * stride + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return out;
}

Uint8List buildPdf(List<PdfImagePage> pages, {String title = 'Скан'}) {
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];
  void raw(String s) => out.add(latin1.encode(s));
  void obj(String body, [List<int>? stream]) {
    offsets.add(out.length);
    raw('${offsets.length} 0 obj\n$body');
    if (stream != null) {
      raw('\nstream\n');
      out.add(stream);
      raw('\nendstream');
    }
    raw('\nendobj\n');
  }

  raw('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  // 1 — каталог, 2 — дерево сторінок; далі на кожну сторінку: сторінка, вміст, зображення.
  final pageIds = [for (var i = 0; i < pages.length; i++) 3 + i * 3];
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Count ${pages.length} /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] >>');
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    final id = pageIds[i];
    final w = p.width * 72 / p.dpi, h = p.height * 72 / p.dpi;
    final ws = w.toStringAsFixed(2), hs = h.toStringAsFixed(2);
    obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $ws $hs] '
        '/Resources << /XObject << /Im0 ${id + 2} 0 R >> >> /Contents ${id + 1} 0 R >>');
    final content = latin1.encode('q $ws 0 0 $hs 0 0 cm /Im0 Do Q');
    obj('<< /Length ${content.length} >>', content);
    switch (p) {
      case JpegPage():
        obj('<< /Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} '
            '/ColorSpace /${p.components == 1 ? 'DeviceGray' : 'DeviceRGB'} /BitsPerComponent 8 '
            '/Filter /DCTDecode /Length ${p.jpeg.length} >>', p.jpeg);
      case BilevelPage():
        final z = zlib.encode(p.bits);
        obj('<< /Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} '
            '/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /FlateDecode /Length ${z.length} >>', z);
    }
  }
  final infoId = offsets.length + 1;
  obj('<< /Producer (KamiDrop) /Title <${_utf16Hex(title)}> >>');

  final xref = out.length;
  raw('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    raw('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  raw('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R /Info $infoId 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.takeBytes();
}

/// Рядок PDF у UTF-16BE (з BOM) — щоб кирилиця в назві не ламалась.
String _utf16Hex(String s) {
  final b = StringBuffer('FEFF');
  for (final c in s.codeUnits) {
    b.write(c.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  return b.toString();
}
