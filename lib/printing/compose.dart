// Макет аркуша: куди й у якому розмірі покласти вміст, поворот, поля, кадрування.
// Чистий Dart (без dart:ui), тож безпечно виконується в окремому ізоляті.
import 'dart:math' as math;
import 'dart:typed_data';

import 'urf.dart';

enum PixelOrder { rgba, bgra }

/// Відрендерений вміст (сторінка PDF, фото, тестова сторінка) у «своїй» орієнтації.
class SourcePixels {
  final Uint8List data; // 4 байти на піксель
  final int width, height;
  final PixelOrder order;
  final bool premultiplied;

  const SourcePixels({
    required this.data,
    required this.width,
    required this.height,
    required this.order,
    this.premultiplied = false,
  });
}

/// Розмір вмісту: пропорції та, якщо відомо, фізичний розмір (для PDF).
class ContentSize {
  final double width, height;
  final double? widthMm, heightMm;
  const ContentSize(this.width, this.height, {this.widthMm, this.heightMm});
  bool get isLandscape => width > height;
}

enum LayoutOrientation { auto, portrait, landscape }

/// Поля аркуша, куди принтер фізично не друкує, мм (для книжкового аркуша; top — верх растру).
class SheetMargins {
  final double top, bottom, left, right;
  const SheetMargins({this.top = 0, this.bottom = 0, this.left = 0, this.right = 0});
  const SheetMargins.all(double v) : this(top: v, bottom: v, left: v, right: v);
  static const zero = SheetMargins();

  bool get isZero => top == 0 && bottom == 0 && left == 0 && right == 0;
}

enum LayoutScale { fit, fill, actual, custom }

enum LayoutAnchor { center, top }

/// Стандартний розмір фото, мм (у книжковій орієнтації: ширина < висоти).
class PhotoSize {
  final String label;
  final double widthMm, heightMm;
  const PhotoSize(this.label, this.widthMm, this.heightMm);

  static const all = [
    PhotoSize('9×13', 89, 127),
    PhotoSize('10×15', 102, 152),
    PhotoSize('13×18', 127, 178),
    PhotoSize('A5', 148, 210),
  ];
}

class LayoutOptions {
  final LayoutOrientation orientation;
  final LayoutScale scale;
  final double customPercent; // для LayoutScale.custom: відсоток від «вписати»
  final double marginMm;
  final LayoutAnchor anchor;
  final PhotoSize? photoSize; // якщо задано — фото кадрується точно під цей розмір
  final bool borderless; // «до краю»: лише для принтерів, що вміють поля 0 (струменеві)

  const LayoutOptions({
    this.orientation = LayoutOrientation.auto,
    this.scale = LayoutScale.fit,
    this.customPercent = 70,
    this.marginMm = 0,
    this.anchor = LayoutAnchor.center,
    this.photoSize,
    this.borderless = false,
  });

  LayoutOptions copyWith({
    LayoutOrientation? orientation,
    LayoutScale? scale,
    double? customPercent,
    double? marginMm,
    LayoutAnchor? anchor,
    PhotoSize? photoSize,
    bool clearPhotoSize = false,
    bool? borderless,
  }) {
    return LayoutOptions(
      orientation: orientation ?? this.orientation,
      scale: scale ?? this.scale,
      customPercent: customPercent ?? this.customPercent,
      marginMm: marginMm ?? this.marginMm,
      anchor: anchor ?? this.anchor,
      photoSize: clearPhotoSize ? null : (photoSize ?? this.photoSize),
      borderless: borderless ?? this.borderless,
    );
  }
}

/// Поля, з якими реально друкуємо: «до краю» прибирає поля принтера, якщо він це вміє.
SheetMargins effectiveMargins(LayoutOptions o, SheetMargins printer, {required bool printerBorderless}) =>
    o.borderless && printerBorderless ? SheetMargins.zero : printer;

/// Результат розрахунку макета. Координати — у «полотні»: аркуш у вибраній орієнтації
/// (для альбомної полотно має розмір pageH×pageW і потім повертається на аркуш).
class PageLayout {
  final bool landscape;
  final int canvasW, canvasH;
  final int renderW, renderH; // у якому розмірі рендерити вміст
  final int ox, oy; // де лежить лівий верхній кут вмісту (може бути від'ємним при кадруванні)
  final int clipX0, clipY0, clipX1, clipY1; // видима область (поля або рамка фото)
  final int safeX0, safeY0, safeX1, safeY1; // область, яку принтер здатен надрукувати

  const PageLayout({
    required this.landscape,
    required this.canvasW,
    required this.canvasH,
    required this.renderW,
    required this.renderH,
    required this.ox,
    required this.oy,
    required this.clipX0,
    required this.clipY0,
    required this.clipX1,
    required this.clipY1,
    this.safeX0 = 0,
    this.safeY0 = 0,
    required this.safeX1,
    required this.safeY1,
  });
}

PageLayout computeLayout(
  ContentSize content,
  LayoutOptions o, {
  required int pageW,
  required int pageH,
  required int dpi,
  SheetMargins printerMargins = SheetMargins.zero,
}) {
  final landscape = switch (o.orientation) {
    LayoutOrientation.auto => content.isLandscape,
    LayoutOrientation.portrait => false,
    LayoutOrientation.landscape => true,
  };
  final cw = landscape ? pageH : pageW;
  final ch = landscape ? pageW : pageH;
  final pxPerMm = dpi / 25.4;
  // Поля принтера в координатах полотна. Альбомне полотно лягає на аркуш повернутим на 90°
  // проти годинникової: його верх — лівий край аркуша, лівий бік — низ аркуша.
  final pm = printerMargins;
  final (hl, ht, hr, hb) = landscape ? (pm.bottom, pm.left, pm.top, pm.right) : (pm.left, pm.top, pm.right, pm.bottom);
  final maxM = math.min(cw, ch) ~/ 3;
  int side(double hwMm) => (math.max(o.marginMm, hwMm) * pxPerMm).round().clamp(0, maxM);
  final ax0 = side(hl), ay0 = side(ht);
  final aw = cw - ax0 - side(hr), ah = ch - ay0 - side(hb);
  final w = content.width, h = content.height;

  double scale;
  int boxX, boxY, boxW, boxH; // видима область

  final photo = o.photoSize;
  if (photo != null) {
    // Рамка фото орієнтована так само, як саме фото; вміст заповнює її з кадруванням.
    var bw = photo.widthMm, bh = photo.heightMm;
    if (content.isLandscape) {
      final t = bw;
      bw = bh;
      bh = t;
    }
    boxW = math.min((bw * pxPerMm).round(), aw);
    boxH = math.min((bh * pxPerMm).round(), ah);
    boxX = o.anchor == LayoutAnchor.top ? ax0 : ax0 + (aw - boxW) ~/ 2;
    boxY = o.anchor == LayoutAnchor.top ? ay0 : ay0 + (ah - boxH) ~/ 2;
    scale = math.max(boxW / w, boxH / h);
  } else {
    final fit = math.min(aw / w, ah / h);
    scale = switch (o.scale) {
      LayoutScale.fit => fit,
      LayoutScale.fill => math.max(aw / w, ah / h),
      LayoutScale.actual => content.widthMm != null ? content.widthMm! * pxPerMm / w : fit,
      LayoutScale.custom => fit * (o.customPercent.clamp(5, 100) / 100),
    };
    boxX = ax0;
    boxY = ay0;
    boxW = aw;
    boxH = ah;
  }

  final rw = math.max(1, (w * scale).round());
  final rh = math.max(1, (h * scale).round());
  final int ox, oy;
  if (photo != null) {
    ox = boxX + (boxW - rw) ~/ 2;
    oy = boxY + (boxH - rh) ~/ 2;
  } else {
    ox = boxX + (boxW - rw) ~/ 2;
    oy = o.anchor == LayoutAnchor.top && rh <= boxH ? boxY : boxY + (boxH - rh) ~/ 2;
  }

  return PageLayout(
    landscape: landscape,
    canvasW: cw,
    canvasH: ch,
    renderW: rw,
    renderH: rh,
    ox: ox,
    oy: oy,
    clipX0: boxX.clamp(0, cw),
    clipY0: boxY.clamp(0, ch),
    clipX1: (boxX + boxW).clamp(0, cw),
    clipY1: (boxY + boxH).clamp(0, ch),
    safeX0: (hl * pxPerMm).round().clamp(0, maxM),
    safeY0: (ht * pxPerMm).round().clamp(0, maxM),
    safeX1: cw - (hr * pxPerMm).round().clamp(0, maxM),
    safeY1: ch - (hb * pxPerMm).round().clamp(0, maxM),
  );
}

/// Складає аркуш: кладе вміст за макетом, обрізає по видимій області, повертає
/// альбомне полотно на 90° проти годинникової стрілки, переводить у сірий або sRGB.
UrfPage composePage(
  SourcePixels src,
  PageLayout lay, {
  required int pageW,
  required int pageH,
  required int dpi,
  required bool color,
}) {
  final bpp = color ? 3 : 1;
  final out = Uint8List(pageW * pageH * bpp)..fillRange(0, pageW * pageH * bpp, 0xff);
  final cw = lay.canvasW;
  final sx0 = math.max(0, lay.clipX0 - lay.ox), sx1 = math.min(src.width, lay.clipX1 - lay.ox);
  final sy0 = math.max(0, lay.clipY0 - lay.oy), sy1 = math.min(src.height, lay.clipY1 - lay.oy);
  final rOff = src.order == PixelOrder.rgba ? 0 : 2;
  final bOff = src.order == PixelOrder.rgba ? 2 : 0;
  final d = src.data;

  for (var sy = sy0; sy < sy1; sy++) {
    final cy = lay.oy + sy;
    for (var sx = sx0; sx < sx1; sx++) {
      final cx = lay.ox + sx;
      final x = lay.landscape ? cy : cx;
      final y = lay.landscape ? cw - 1 - cx : cy;
      if (x < 0 || y < 0 || x >= pageW || y >= pageH) continue;
      final si = (sy * src.width + sx) * 4;
      var r = d[si + rOff], g = d[si + 1], b = d[si + bOff];
      final a = d[si + 3];
      if (a != 255) {
        final inv = 255 - a; // накладаємо на білий папір
        if (src.premultiplied) {
          r += inv;
          g += inv;
          b += inv;
        } else {
          r = (r * a + 255 * inv) ~/ 255;
          g = (g * a + 255 * inv) ~/ 255;
          b = (b * a + 255 * inv) ~/ 255;
        }
      }
      final o = (y * pageW + x) * bpp;
      if (color) {
        out[o] = r;
        out[o + 1] = g;
        out[o + 2] = b;
      } else {
        out[o] = (r * 299 + g * 587 + b * 114 + 500) ~/ 1000;
      }
    }
  }
  return UrfPage(width: pageW, height: pageH, dpi: dpi, color: color, pixels: out);
}

/// Розбирає «1-3, 5, 8-» у список індексів (з нуля). Порожній рядок — усі сторінки.
/// Повертає null, якщо введено щось некоректне.
List<int>? parsePageRange(String input, int pageCount) {
  final text = input.replaceAll(' ', '');
  if (text.isEmpty) return List<int>.generate(pageCount, (i) => i);
  final result = <int>[];
  for (final part in text.split(',')) {
    if (part.isEmpty) continue;
    final dash = part.indexOf('-');
    int from, to;
    if (dash < 0) {
      final v = int.tryParse(part);
      if (v == null) return null;
      from = to = v;
    } else {
      final a = part.substring(0, dash), b = part.substring(dash + 1);
      from = a.isEmpty ? 1 : (int.tryParse(a) ?? -1);
      to = b.isEmpty ? pageCount : (int.tryParse(b) ?? -1);
    }
    if (from < 1 || to < from || to > pageCount) return null;
    for (var p = from; p <= to; p++) {
      result.add(p - 1);
    }
  }
  return result.isEmpty ? null : result;
}
