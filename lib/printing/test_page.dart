import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class RenderedPage {
  final Uint8List rgba;
  final int width, height;
  RenderedPage(this.rgba, this.width, this.height);
}

int a4WidthPx(int dpi) => (210 / 25.4 * dpi).round();
int a4HeightPx(int dpi) => (297 / 25.4 * dpi).round();

/// Малює тестову сторінку A4: рамки 3/5/10 мм, стрілка «UP», градієнт, кольорові плашки, дрібний текст.
Future<RenderedPage> renderTestPage({
  required int pageNumber,
  required int dpi,
  required bool color,
  required String info,
}) async {
  final w = a4WidthPx(dpi), h = a4HeightPx(dpi);
  final mm = dpi / 25.4;
  const black = ui.Color(0xFF000000);
  final recorder = ui.PictureRecorder();
  final c = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

  void text(String s, double size, ui.Offset at, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: black, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center ? at - ui.Offset(tp.width / 2, tp.height / 2) : at);
    tp.dispose();
  }

  c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

  // Рамки: видно, де принтер обрізає поле.
  for (final (inset, width) in const [(3, 1.0), (5, 2.0), (10, 3.0)]) {
    final o = inset * mm;
    c.drawRect(
      ui.Rect.fromLTRB(o, o, w - o, h - o),
      ui.Paint()
        ..color = black
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = width * dpi / 300,
    );
    text('$inset mm', 3 * mm, ui.Offset(o + 5 + inset * 8 * mm, o + 5));
  }

  text('KamiDrop', 14 * mm, ui.Offset(w / 2, 45 * mm), center: true);
  text('page $pageNumber — ${pageNumber.isOdd ? 'FRONT' : 'BACK'}', 6 * mm, ui.Offset(w / 2, 65 * mm), center: true);

  // Стрілка вгору — для перевірки орієнтації зворотного боку при дуплексі.
  final cx = w / 2, top = 85 * mm;
  final arrow = ui.Path()
    ..moveTo(cx, top)
    ..lineTo(cx - 15 * mm, top + 20 * mm)
    ..lineTo(cx - 5 * mm, top + 20 * mm)
    ..lineTo(cx - 5 * mm, top + 45 * mm)
    ..lineTo(cx + 5 * mm, top + 45 * mm)
    ..lineTo(cx + 5 * mm, top + 20 * mm)
    ..lineTo(cx + 15 * mm, top + 20 * mm)
    ..close();
  c.drawPath(arrow, ui.Paint()..color = black);
  text('UP', 6 * mm, ui.Offset(cx, top + 52 * mm), center: true);

  // Градієнт і кольорові плашки.
  final gx0 = 20 * mm, gx1 = w - 20 * mm, gy = 160 * mm;
  c.drawRect(
    ui.Rect.fromLTRB(gx0, gy, gx1, gy + 15 * mm),
    ui.Paint()..shader = ui.Gradient.linear(ui.Offset(gx0, 0), ui.Offset(gx1, 0), const [black, ui.Color(0xFFFFFFFF)]),
  );
  if (color) {
    const swatches = [
      ui.Color(0xFFFF0000), ui.Color(0xFF00AA00), ui.Color(0xFF0000FF),
      ui.Color(0xFF00C8FF), ui.Color(0xFFFF00C8), ui.Color(0xFFFFDC00),
    ];
    final sw = (gx1 - gx0) / swatches.length;
    for (var i = 0; i < swatches.length; i++) {
      c.drawRect(ui.Rect.fromLTWH(gx0 + i * sw, gy + 20 * mm, sw, 15 * mm), ui.Paint()..color = swatches[i]);
    }
  }

  // Дрібний текст — перевірка різкості.
  var y = 205 * mm;
  for (final pt in const [6, 8, 10, 12]) {
    final px = pt / 72 * dpi;
    text('$pt pt: The quick brown fox jumps over the lazy dog 0123456789', px, ui.Offset(gx0, y));
    y += px * 1.6;
  }
  text(info, 3.5 * mm, ui.Offset(gx0, h - 25 * mm));

  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return RenderedPage(bytes!.buffer.asUint8List(), w, h);
}
