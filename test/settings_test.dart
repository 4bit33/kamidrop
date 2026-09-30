import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/printing/compose.dart';
import 'package:kamidrop/settings.dart';

void main() {
  test('Налаштування переживають збереження в JSON', () {
    final s = KamiSettings()
      ..remember(
        printerId: 'xerox',
        prefs: const PrinterPrefs(color: false, duplex: true),
        document: false,
        layout: const LayoutOptions(
          orientation: LayoutOrientation.landscape,
          photoSize: PhotoSize('10×15', 102, 152),
          anchor: LayoutAnchor.top,
          marginMm: 0,
        ),
      );
    s.rememberLayout = true;
    final back = KamiSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.lastPrinterId, 'xerox');
    expect(back.printers['xerox']!.duplex, isTrue);
    expect(back.printers['xerox']!.color, isFalse);
    final photo = back.layoutFor(document: false);
    expect(photo.orientation, LayoutOrientation.landscape);
    expect(photo.photoSize?.label, '10×15');
    expect(photo.anchor, LayoutAnchor.top);
    expect(photo.marginMm, 0);
    expect(back.layoutFor(document: true).scale, LayoutScale.fit, reason: 'документів не чіпали');
  });

  test('Тестова сторінка не перезаписує макет', () {
    final s = KamiSettings(photoLayout: const LayoutOptions(marginMm: 10), rememberLayout: true)
      ..remember(printerId: 'b', prefs: const PrinterPrefs(color: true, duplex: false), document: false);
    expect(s.layoutFor(document: false).marginMm, 10);
    expect(s.lastPrinterId, 'b');
  });

  test('Невідомі значення зі старих налаштувань замінюються типовими', () {
    final o = layoutFromJson({'orientation': 'diagonal', 'scale': 'fill', 'photoSize': '30×40'});
    expect(o.orientation, LayoutOrientation.auto);
    expect(o.scale, LayoutScale.fill);
    expect(o.photoSize, isNull);
  });

  test('Перемикачі: типові значення, збереження, «не пам\'ятати макет»', () {
    final d = KamiSettings();
    expect(d.autoOpenShared, isFalse);
    expect(d.lastPrinterFirst, isFalse);
    expect(d.rememberLayout, isFalse);
    final s = KamiSettings(photoLayout: const LayoutOptions(marginMm: 10), autoOpenShared: true)
      ..rememberLayout = false;
    expect(s.layoutFor(document: false).marginMm, 5, reason: 'типовий макет фото');
    final back = KamiSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.autoOpenShared, isTrue);
    expect(back.rememberLayout, isFalse);
    expect(back.photoLayout?.marginMm, 10, reason: 'збережений макет не губиться, лише не застосовується');
  });

  test('Підказка: вдруге той самий нетиповий макет, лише один раз', () {
    const prefs = PrinterPrefs(color: true, duplex: false);
    const tenByFifteen = LayoutOptions(photoSize: PhotoSize('10×15', 102, 152));
    final s = KamiSettings();
    void printPhoto(LayoutOptions l) => s.remember(printerId: 'b', prefs: prefs, document: false, layout: l);

    printPhoto(tenByFifteen);
    expect(s.shouldHintLayout(document: false), isFalse, reason: 'перший раз');
    printPhoto(const LayoutOptions(marginMm: 5)); // типовий — серія обривається
    printPhoto(tenByFifteen);
    expect(s.shouldHintLayout(document: false), isFalse);
    printPhoto(tenByFifteen);
    expect(s.shouldHintLayout(document: false), isTrue, reason: 'вдруге поспіль той самий');
    expect(s.shouldHintLayout(document: true), isFalse, reason: 'документи рахуються окремо');
    s.layoutHintShown = true;
    printPhoto(tenByFifteen);
    expect(s.shouldHintLayout(document: false), isFalse, reason: 'лише раз');
    expect(s.layoutFor(document: false).photoSize, isNull, reason: 'вимкнено — макет типовий');
    s.rememberLayout = true;
    expect(s.layoutFor(document: false).photoSize?.label, '10×15', reason: 'увімкнули — вже готовий');
  });
}
