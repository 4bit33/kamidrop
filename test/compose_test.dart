import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/printing/compose.dart';

PageLayout _simple({required bool landscape, required int cw, required int ch, required int w, required int h, int ox = 0, int oy = 0}) {
  return PageLayout(
    landscape: landscape,
    canvasW: cw,
    canvasH: ch,
    renderW: w,
    renderH: h,
    ox: ox,
    oy: oy,
    clipX0: 0,
    clipY0: 0,
    clipX1: cw,
    clipY1: ch,
  );
}

void main() {
  const a4 = ContentSize(595, 842, widthMm: 210, heightMm: 297); // A4 у пунктах
  const pageW = 2480, pageH = 3508, dpi = 300;

  test('Діапазони сторінок', () {
    expect(parsePageRange('', 3), [0, 1, 2]);
    expect(parsePageRange('1-3, 5', 6), [0, 1, 2, 4]);
    expect(parsePageRange('4-', 6), [3, 4, 5]);
    expect(parsePageRange('-2', 6), [0, 1]);
    expect(parsePageRange('7', 6), isNull);
    expect(parsePageRange('3-1', 6), isNull);
    expect(parsePageRange('abc', 6), isNull);
  });

  test('Вписати: книжкова A4 займає весь аркуш', () {
    final l = computeLayout(a4, const LayoutOptions(), pageW: pageW, pageH: pageH, dpi: dpi);
    expect(l.landscape, isFalse);
    expect(l.renderW, closeTo(pageW, 3));
    expect(l.renderH, closeTo(pageH, 3));
  });

  test('Авто-орієнтація: альбомний вміст кладеться на альбомне полотно', () {
    const land = ContentSize(842, 595);
    final l = computeLayout(land, const LayoutOptions(), pageW: pageW, pageH: pageH, dpi: dpi);
    expect(l.landscape, isTrue);
    expect(l.canvasW, pageH);
    expect(l.canvasH, pageW);
    final forced = computeLayout(land, const LayoutOptions(orientation: LayoutOrientation.portrait),
        pageW: pageW, pageH: pageH, dpi: dpi);
    expect(forced.landscape, isFalse);
    expect(forced.renderW, closeTo(pageW, 3), reason: 'альбомне на книжковому — по ширині аркуша');
  });

  test('Поля зменшують вміст', () {
    final l = computeLayout(a4, const LayoutOptions(marginMm: 10), pageW: pageW, pageH: pageH, dpi: dpi);
    final m = (10 * dpi / 25.4).round();
    expect(l.clipX0, m);
    expect(l.renderH, lessThanOrEqualTo(pageH - 2 * m));
  });

  test('100 %: A4-сторінка PDF має свій фізичний розмір', () {
    const a5 = ContentSize(420, 595, widthMm: 148, heightMm: 210);
    final l = computeLayout(a5, const LayoutOptions(scale: LayoutScale.actual), pageW: pageW, pageH: pageH, dpi: dpi);
    expect(l.renderW, closeTo(148 * dpi / 25.4, 3));
  });

  test('Фото 10×15: рамка точного розміру, кадрування, розташування вгорі', () {
    const photo = ContentSize(4000, 3000); // альбомне фото 4:3
    final l = computeLayout(
      photo,
      const LayoutOptions(orientation: LayoutOrientation.portrait, photoSize: PhotoSize('10×15', 102, 152), anchor: LayoutAnchor.top),
      pageW: pageW,
      pageH: pageH,
      dpi: dpi,
    );
    final pxPerMm = dpi / 25.4;
    expect(l.clipX1 - l.clipX0, closeTo(152 * pxPerMm, 2), reason: 'альбомна рамка 15 см завширшки');
    expect(l.clipY1 - l.clipY0, closeTo(102 * pxPerMm, 2));
    expect(l.clipX0, 0);
    expect(l.clipY0, 0);
    expect(l.renderW, greaterThanOrEqualTo(l.clipX1 - l.clipX0));
    expect(l.renderH, greaterThanOrEqualTo(l.clipY1 - l.clipY0));
  });

  test('Складання аркуша: центр, BGRA, білий папір навколо', () {
    // Вміст 2×1: лівий піксель чорний, правий — червоний (BGRA).
    final data = Uint8List.fromList([0, 0, 0, 255, 0, 0, 255, 255]);
    final src = SourcePixels(data: data, width: 2, height: 1, order: PixelOrder.bgra);
    final page = composePage(src, _simple(landscape: false, cw: 4, ch: 3, w: 2, h: 1, ox: 1, oy: 1),
        pageW: 4, pageH: 3, dpi: 72, color: true);
    int at(int x, int y, int c) => page.pixels[(y * 4 + x) * 3 + c];
    expect([at(1, 1, 0), at(1, 1, 1), at(1, 1, 2)], [0, 0, 0]);
    expect([at(2, 1, 0), at(2, 1, 1), at(2, 1, 2)], [255, 0, 0]);
    expect(at(0, 0, 0), 255);
  });

  test('Складання аркуша: альбомне полотно повертається проти годинникової', () {
    final data = Uint8List.fromList([0, 0, 0, 255, 0, 0, 255, 255]); // чорний, червоний
    final src = SourcePixels(data: data, width: 2, height: 1, order: PixelOrder.bgra);
    // Аркуш 1×2 (книжковий), полотно 2×1 (альбомне).
    final page = composePage(src, _simple(landscape: true, cw: 2, ch: 1, w: 2, h: 1), pageW: 1, pageH: 2, dpi: 72, color: false);
    expect(page.pixels[0], 76, reason: 'правий (червоний) край полотна стає верхом аркуша');
    expect(page.pixels[1], 0);
  });

  test('Кадрування: вміст за межами рамки не друкується', () {
    final data = Uint8List(4 * 4 * 4); // 4×4 чорних прозорих... робимо непрозорими
    for (var i = 3; i < data.length; i += 4) {
      data[i] = 255;
    }
    final src = SourcePixels(data: data, width: 4, height: 4, order: PixelOrder.rgba);
    const lay = PageLayout(
      landscape: false, canvasW: 4, canvasH: 4, renderW: 4, renderH: 4, ox: 0, oy: 0,
      clipX0: 1, clipY0: 1, clipX1: 3, clipY1: 3, // лише центр 2×2
    );
    final page = composePage(src, lay, pageW: 4, pageH: 4, dpi: 72, color: false);
    expect(page.pixels[0], 255, reason: 'кут поза рамкою лишається білим');
    expect(page.pixels[1 * 4 + 1], 0);
    expect(page.pixels[2 * 4 + 2], 0);
    expect(page.pixels[3 * 4 + 3], 255);
  });

  test('Напівпрозорий піксель накладається на білий', () {
    final page = composePage(
      SourcePixels(data: Uint8List.fromList([0, 0, 0, 128]), width: 1, height: 1, order: PixelOrder.rgba),
      _simple(landscape: false, cw: 1, ch: 1, w: 1, h: 1),
      pageW: 1,
      pageH: 1,
      dpi: 72,
      color: false,
    );
    expect(page.pixels[0], closeTo(127, 1));
  });
}
