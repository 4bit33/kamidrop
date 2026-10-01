import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/printing/collage.dart';
import 'package:kamidrop/printing/sources.dart';
import 'package:kamidrop/ui/collage_editor.dart';

void main() {
  late Collage collage;
  late CollageItem a, b;

  Future<Rect> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    a = CollageItem(photo: 0, x: 10, y: 10, w: 90, h: 60);
    b = CollageItem(photo: 1, x: 110, y: 10, w: 90, h: 60);
    collage = Collage([(3000, 2000), (3000, 2000)], [
      [a, b],
    ]);
    // Декодування картинок — справжня асинхронність, у фейковому часі тесту без runAsync зависає.
    final thumbs = (await tester.runAsync(() async =>
        [await createTestImage(width: 30, height: 20), await createTestImage(width: 30, height: 20)]))!;
    await tester.pumpWidget(MaterialApp(
      home: CollageEditorScreen(source: CollageSource(<ImageSource>[], collage), thumbs: thumbs),
    ));
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(const ValueKey('collage-sheet')));
  }

  testWidgets('Тримати фото й свайпнути іншим пальцем — фото на новому аркуші', (tester) async {
    final sheet = await pumpEditor(tester);
    final k = sheet.width / a4WidthMm;
    Offset at(double xMm, double yMm) => sheet.topLeft + Offset(xMm * k, yMm * k);

    final hold = await tester.startGesture(at(50, 40), pointer: 1); // на фото A
    await tester.pump();
    final swipe = await tester.startGesture(at(150, 200), pointer: 2); // поза фото
    await swipe.moveBy(const Offset(-120, 0));
    await tester.pump();
    await swipe.up();
    await hold.up();
    await tester.pumpAndSettle();

    expect(collage.sheets.length, 2, reason: 'за останнім аркушем створився новий');
    expect(collage.sheets[1], [a]);
    expect(collage.sheets[0], [b]);
    expect([a.x, a.y], [10, 10], reason: 'на тому самому місці');
    expect(find.text('Фото на аркуші 2'), findsOneWidget);
  });

  testWidgets('Два пальці на фото — масштаб, без перенесення', (tester) async {
    final sheet = await pumpEditor(tester);
    final k = sheet.width / a4WidthMm;
    Offset at(double xMm, double yMm) => sheet.topLeft + Offset(xMm * k, yMm * k);

    final f1 = await tester.startGesture(at(40, 40), pointer: 1);
    await tester.pump();
    final f2 = await tester.startGesture(at(60, 40), pointer: 2); // теж на фото A
    await f1.moveBy(Offset(-10 * k, 0));
    await f2.moveBy(Offset(10 * k, 0));
    await tester.pump();
    await f1.up();
    await f2.up();
    await tester.pumpAndSettle();

    expect(collage.sheets.length, 1);
    expect(a.w, closeTo(180, 1), reason: 'відстань між пальцями вдвічі більша');
    expect(a.w / a.h, closeTo(1.5, 0.01), reason: 'пропорції рамки ті самі');
  });

  testWidgets('Подвійний тап — кадрування, тягнути — зсув кадру', (tester) async {
    final sheet = await pumpEditor(tester);
    final k = sheet.width / a4WidthMm;
    Offset at(double xMm, double yMm) => sheet.topLeft + Offset(xMm * k, yMm * k);
    // Рамка 10×15 для фото 3:2 = майже без запасу; беремо квадратну рамку — запас по ширині є.
    a
      ..w = 60
      ..h = 60;

    await tester.tapAt(at(40, 40));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(at(40, 40));
    await tester.pumpAndSettle();
    expect(find.textContaining('Кадрування'), findsOneWidget);

    final g = await tester.startGesture(at(40, 40));
    await g.moveBy(Offset(10 * k, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(a.panX, closeTo(10 / 15, 0.01), reason: 'фото 90 мм у рамці 60 — запас по 15 мм');
    expect([a.x, a.y], [10, 10], reason: 'рамка на місці');
  });
}
