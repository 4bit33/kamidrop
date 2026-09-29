import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/printing/urf.dart';

UrfPage _randomPage(Random rnd, int w, int h, {required bool color, int levels = 3}) {
  final bpp = color ? 3 : 1;
  final px = Uint8List(w * h * bpp);
  for (var i = 0; i < px.length; i++) {
    px[i] = rnd.nextInt(levels) * 100; // мало рівнів -> і серії, і літерали
  }
  // кілька однакових рядків підряд
  for (var y = 5; y < 9 && y < h; y++) {
    px.setRange(y * w * bpp, (y + 1) * w * bpp, px, 4 * w * bpp);
  }
  return UrfPage(width: w, height: h, dpi: 300, color: color, pixels: px);
}

void main() {
  test('URF: кодування і декодування дають ті самі пікселі', () {
    final rnd = Random(42);
    for (final color in [false, true]) {
      final pages = [_randomPage(rnd, 777, 40, color: color), _randomPage(rnd, 300, 300, color: color, levels: 1)];
      final data = encodeUrf(pages, duplex: UrfDuplex.longEdge);
      expect(String.fromCharCodes(data.sublist(0, 7)), 'UNIRAST');
      final decoded = decodeUrf(data);
      expect(decoded.length, 2);
      for (var i = 0; i < 2; i++) {
        expect(decoded[i].width, pages[i].width);
        expect(decoded[i].height, pages[i].height);
        expect(decoded[i].color, color);
        expect(decoded[i].pixels, pages[i].pixels);
      }
      expect(data[12 + 2], 3, reason: 'байт дуплексу = long edge');
    }
  });

  test('URF: довгі серії (>128) і рядки, що повторюються >256 разів', () {
    final page = UrfPage(width: 1000, height: 700, dpi: 600, color: false, pixels: Uint8List(700000)..fillRange(0, 700000, 255));
    final data = encodeUrf([page]);
    expect(data.length, lessThan(200));
    expect(decodeUrf(data).single.pixels, page.pixels);
  });

  test('Зворотний бік: rotated повертає на 180°', () {
    final page = UrfPage(width: 2, height: 2, dpi: 300, color: false, pixels: Uint8List.fromList([1, 2, 3, 4]));
    expect(page.forBackSide(SheetBack.rotated, tumble: false).pixels, [4, 3, 2, 1]);
    expect(page.forBackSide(SheetBack.normal, tumble: false).pixels, [1, 2, 3, 4]);
    expect(page.forBackSide(SheetBack.flipped, tumble: false).pixels, [3, 4, 1, 2]);
    expect(page.forBackSide(SheetBack.flipped, tumble: true).pixels, [2, 1, 4, 3]);
  });

  test('RGBA -> сірий', () {
    final rgba = Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255]);
    final p = UrfPage.fromRgba(rgba, 2, 1, 300, color: false);
    expect(p.pixels, [255, 0]);
  });
}
