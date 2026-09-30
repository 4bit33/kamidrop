import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/printing/collage.dart';
import 'package:kamidrop/printing/compose.dart';

void main() {
  test('Авторозкладка: два фото 3:2 з довгим боком 15 см влазять на один A4', () {
    final c = autoArrange([(3000, 2000), (3000, 2000)]);
    expect(c.sheets.length, 1);
    final a = c.sheets.single;
    expect(a.length, 2);
    for (final item in a) {
      expect([item.w, item.h]..sort(), [closeTo(101.33, 0.01), closeTo(152, 0.01)]);
      expect(item.right, lessThanOrEqualTo(a4WidthMm - 5 + 1e-6));
      expect(item.bottom, lessThanOrEqualTo(a4HeightMm - 5 + 1e-6));
    }
    expect(a[0].bottom <= a[1].y || a[0].right <= a[1].x, isTrue, reason: 'не накладаються');
  });

  test('Авторозкладка: зайві фото переходять на наступний аркуш', () {
    final c = autoArrange(List.filled(5, (3000.0, 2000.0)));
    expect(c.sheets.length, 3);
    expect(c.sheets.map((s) => s.length), [2, 2, 1]);
    expect(c.sheets.expand((s) => s).map((i) => i.photo), [0, 1, 2, 3, 4]);
  });

  test('Вільне полотно: рамка з пропорціями фото — нічого не обрізається', () {
    final item = CollageItem(photo: 0, x: 10, y: 20, w: 150, h: 100);
    final (x, y, w, h) = contentRect(item, 1.5);
    expect([x, y, w, h], [10, 20, 150, 100]);
  });

  test('Кадрування: вміст заповнює рамку, pan зсуває в межах запасу', () {
    final item = CollageItem(photo: 0, x: 0, y: 0, w: 100, h: 100);
    final (x0, _, w0, h0) = contentRect(item, 2); // широке фото в квадратній рамці
    expect([w0, h0], [200, 100]);
    expect(x0, -50, reason: 'по центру');
    item.panX = 1;
    expect(contentRect(item, 2).$1, 0, reason: 'видно лівий край фото');
    item.panX = -1;
    expect(contentRect(item, 2).$1, -100, reason: 'видно правий край');
  });

  test('Складання: фото на місці, поворот за годинниковою, решта — білий папір', () {
    // Фото 2×1: лівий піксель червоний, правий синій (RGBA).
    final src = SourcePixels(
      data: Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]),
      width: 2,
      height: 1,
      order: PixelOrder.rgba,
    );
    // Поворот на 90° за годинниковою: вміст 1×2 — зверху червоний, знизу синій.
    final sheet = composeCollageSheet(3, 3, [
      PlacedPhoto(pixels: src, quarterTurns: 1, frame: (1, 0, 2, 2), content: (1, 0, 2, 2)),
    ]);
    List<int> at(int x, int y) => sheet.sublist((y * 3 + x) * 4, (y * 3 + x) * 4 + 3);
    expect(at(1, 0), [255, 0, 0]);
    expect(at(1, 1), [0, 0, 255]);
    expect(at(0, 0), [255, 255, 255]);
    expect(at(1, 2), [255, 255, 255]);
  });

  test('Складання: вміст за рамкою обрізається', () {
    final src = SourcePixels(data: Uint8List(4 * 4 * 4), width: 4, height: 4, order: PixelOrder.rgba);
    for (var i = 3; i < src.data.length; i += 4) {
      src.data[i] = 255; // непрозорий чорний
    }
    final sheet = composeCollageSheet(4, 4, [
      PlacedPhoto(pixels: src, quarterTurns: 0, frame: (1, 1, 3, 3), content: (0, 0, 4, 4)),
    ]);
    expect(sheet[0], 255, reason: 'кут поза рамкою білий');
    expect(sheet[(1 * 4 + 1) * 4], 0);
    expect(sheet[(3 * 4 + 3) * 4], 255);
  });

  test('Вільне місце: під уже розкладеним фото, або null, якщо не влазить', () {
    final sheet = [CollageItem(photo: 0, x: 5, y: 5, w: 152, h: 101)];
    final spot = findFreeSpot(sheet, 152, 101);
    expect(spot, isNotNull);
    expect(spot!.$2, greaterThanOrEqualTo(5 + 101 + 3));
    sheet.add(CollageItem(photo: 1, x: spot.$1, y: spot.$2, w: 152, h: 101));
    expect(findFreeSpot(sheet, 152, 101), isNull, reason: 'третє 10×15 на A4 не влазить');
    final (fw, fh) = frameForLongSide(1.5, 152);
    expect(fw, 152);
    expect(fh, closeTo(101.33, 0.01));
  });

  test('Авторозкладка не повертає фото набік без потреби', () {
    final c = autoArrange([(3000, 2000), (2400, 1800), (2000, 3000)]);
    expect(c.sheets.expand((s) => s).every((i) => i.quarterTurns == 0), isTrue);
    final vertical = c.sheets.expand((s) => s).firstWhere((i) => i.photo == 2);
    expect(vertical.h, greaterThan(vertical.w), reason: 'вертикальне лишається вертикальним');
  });
}
