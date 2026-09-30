// Кілька фото на аркуші: модель, авторозкладка і складання аркуша в пікселі.
// Чистий Dart (без dart:ui), тож безпечно виконується в окремому ізоляті.
import 'dart:math' as math;
import 'dart:typed_data';

import 'compose.dart';

const a4WidthMm = 210.0, a4HeightMm = 297.0;

/// Фото на аркуші. Координати — мм на книжковому A4 від лівого верхнього кута.
/// [x], [y], [w], [h] — рамка (видима область). Фото заповнює рамку з кадруванням: на вільному
/// полотні рамка має пропорції фото, тож нічого не обрізається; шаблони задаватимуть свої рамки.
class CollageItem {
  CollageItem({
    required this.photo,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.quarterTurns = 0,
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
  });

  int photo; // індекс у списку фото колажу
  double x, y, w, h;
  int quarterTurns; // поворот фото на 90° за годинниковою
  double zoom; // ≥ 1: наближення всередині рамки (кадрування)
  double panX, panY; // −1…1: зсув кадру всередині рамки

  CollageItem copy() => CollageItem(
      photo: photo, x: x, y: y, w: w, h: h, quarterTurns: quarterTurns, zoom: zoom, panX: panX, panY: panY);

  double get right => x + w;
  double get bottom => y + h;
}

/// Колаж: фото (пропорції кожного, ширина/висота в пікселях) і аркуші з розкладеними фото.
class Collage {
  Collage(this.photoSizes, [List<List<CollageItem>>? sheets]) : sheets = sheets ?? [[]];

  final List<(double, double)> photoSizes;
  final List<List<CollageItem>> sheets;

  /// Пропорції фото з урахуванням повороту (ширина / висота).
  double aspectOf(CollageItem item) {
    final (w, h) = photoSizes[item.photo];
    return item.quarterTurns.isOdd ? h / w : w / h;
  }

  void removeEmptySheets() {
    sheets.removeWhere((s) => s.isEmpty);
    if (sheets.isEmpty) sheets.add([]);
  }
}

/// Розкладає фото рядками зліва направо, зверху вниз, переходячи на новий аркуш, коли місця
/// не лишилося. Довший бік кожного фото — [longSideMm]; фото повертається на 90° лише тоді,
/// коли інакше не влазить у поточне місце (люди чекають, що фото стоятимуть рівно). [marginMm] — поля від краю аркуша, [gapMm] — проміжок між фото.
Collage autoArrange(
  List<(double, double)> photoSizes, {
  double longSideMm = 152,
  double marginMm = 5,
  double gapMm = 3,
}) {
  final collage = Collage(photoSizes);
  final maxW = a4WidthMm - 2 * marginMm, maxH = a4HeightMm - 2 * marginMm;
  var sheet = collage.sheets.first;
  var cx = marginMm, cy = marginMm, rowH = 0.0;

  for (var i = 0; i < photoSizes.length; i++) {
    final (pw, ph) = photoSizes[i];
    // Розмір рамки в обох орієнтаціях; не більший за аркуш.
    (double, double, int) frame(int turns) {
      var a = turns.isOdd ? ph / pw : pw / ph;
      var w = a >= 1 ? longSideMm : longSideMm * a;
      var h = a >= 1 ? longSideMm / a : longSideMm;
      final k = math.min(1.0, math.min(maxW / w, maxH / h));
      return (w * k, h * k, turns);
    }

    final options = [frame(0), frame(1)];
    (double, double, int)? fits(double x, double y) {
      // Спершу — як є; набік лише тоді, коли інакше тут не влазить.
      return options
          .where((f) => x + f.$1 <= a4WidthMm - marginMm + 1e-6 && y + f.$2 <= a4HeightMm - marginMm + 1e-6)
          .firstOrNull;
    }

    var f = fits(cx, cy);
    if (f == null) {
      // Новий рядок.
      cx = marginMm;
      cy += rowH + gapMm;
      rowH = 0;
      f = fits(cx, cy);
    }
    if (f == null) {
      // Новий аркуш.
      sheet = [];
      collage.sheets.add(sheet);
      cx = marginMm;
      cy = marginMm;
      rowH = 0;
      f = fits(cx, cy) ?? options.first;
    }
    sheet.add(CollageItem(photo: i, x: cx, y: cy, w: f.$1, h: f.$2, quarterTurns: f.$3));
    cx += f.$1 + gapMm;
    rowH = math.max(rowH, f.$2);
  }
  return collage;
}

/// Де лежить фото відносно рамки (у тих самих одиницях, що й рамка): фото заповнює рамку
/// («cover»), наближене на [CollageItem.zoom] і зсунуте на pan. Повертає (x, y, w, h).
(double, double, double, double) contentRect(CollageItem item, double aspect, {double scale = 1}) {
  final fw = item.w * scale, fh = item.h * scale;
  var cw = fw, ch = fw / aspect;
  if (ch < fh) {
    ch = fh;
    cw = fh * aspect;
  }
  cw *= item.zoom;
  ch *= item.zoom;
  final fx = item.x * scale, fy = item.y * scale;
  final cx = fx + (fw - cw) / 2 * (1 - item.panX);
  final cy = fy + (fh - ch) / 2 * (1 - item.panY);
  return (cx, cy, cw, ch);
}

/// Фото, відрендерене для аркуша: [pixels] у своїй (неповернутій) орієнтації, розміром із
/// вміст після повороту; [frame] і [content] — прямокутники на аркуші в пікселях.
class PlacedPhoto {
  const PlacedPhoto({required this.pixels, required this.quarterTurns, required this.frame, required this.content});

  final SourcePixels pixels;
  final int quarterTurns;
  final (int, int, int, int) frame; // x0, y0, x1, y1
  final (int, int, int, int) content; // x0, y0, x1, y1
}

/// Складає аркуш (RGBA, білий фон): кожне фото повертається й обрізається по своїй рамці.
Uint8List composeCollageSheet(int width, int height, List<PlacedPhoto> photos) {
  final out = Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);
  for (final p in photos) {
    final src = p.pixels;
    final (fx0, fy0, fx1, fy1) = p.frame;
    final (cx0, cy0, cx1, cy1) = p.content;
    final cw = cx1 - cx0, ch = cy1 - cy0;
    if (cw <= 0 || ch <= 0) continue;
    final rOff = src.order == PixelOrder.rgba ? 0 : 2, bOff = src.order == PixelOrder.rgba ? 2 : 0;
    final x0 = math.max(0, math.max(fx0, cx0)), x1 = math.min(width, math.min(fx1, cx1));
    final y0 = math.max(0, math.max(fy0, cy0)), y1 = math.min(height, math.min(fy1, cy1));
    final t = p.quarterTurns % 4;
    for (var y = y0; y < y1; y++) {
      final v = y - cy0; // позиція у вмісті після повороту
      for (var x = x0; x < x1; x++) {
        final u = x - cx0;
        // Точка вмісту (u, v) → піксель неповернутого фото (за годинниковою).
        int sx, sy;
        switch (t) {
          case 1:
            sx = v * src.width ~/ ch;
            sy = (cw - 1 - u) * src.height ~/ cw;
          case 2:
            sx = (cw - 1 - u) * src.width ~/ cw;
            sy = (ch - 1 - v) * src.height ~/ ch;
          case 3:
            sx = (ch - 1 - v) * src.width ~/ ch;
            sy = u * src.height ~/ cw;
          default:
            sx = u * src.width ~/ cw;
            sy = v * src.height ~/ ch;
        }
        final si = (sy * src.width + sx) * 4;
        final d = src.data;
        final a = d[si + 3];
        final o = (y * width + x) * 4;
        if (a == 255) {
          out[o] = d[si + rOff];
          out[o + 1] = d[si + 1];
          out[o + 2] = d[si + bOff];
        } else {
          final inv = 255 - a; // на білий папір
          out[o] = (d[si + rOff] * a + 255 * inv) ~/ 255;
          out[o + 1] = (d[si + 1] * a + 255 * inv) ~/ 255;
          out[o + 2] = (d[si + bOff] * a + 255 * inv) ~/ 255;
        }
      }
    }
  }
  return out;
}

/// Перше вільне місце для рамки [w]×[h] на аркуші (крок 5 мм, зверху вниз, зліва направо),
/// або null, якщо не влазить без накладання.
(double, double)? findFreeSpot(List<CollageItem> sheet, double w, double h, {double marginMm = 5, double gapMm = 3}) {
  bool overlaps(double x, double y) => sheet.any((o) =>
      x < o.right + gapMm && x + w + gapMm > o.x && y < o.bottom + gapMm && y + h + gapMm > o.y);
  for (var y = marginMm; y + h <= a4HeightMm - marginMm + 1e-6; y += 5) {
    for (var x = marginMm; x + w <= a4WidthMm - marginMm + 1e-6; x += 5) {
      if (!overlaps(x, y)) return (x, y);
    }
  }
  return null;
}

/// Розмір рамки з довгим боком [longSideMm] для пропорцій [aspect] (ширина / висота).
(double, double) frameForLongSide(double aspect, double longSideMm) =>
    aspect >= 1 ? (longSideMm, longSideMm / aspect) : (longSideMm * aspect, longSideMm);
