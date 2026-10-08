import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/l10n/l10n.dart';
import 'package:kamidrop/main.dart';

void main() {
  tearDown(() => appLanguage.value = 'system');

  testWidgets('Українська система — інтерфейс українською', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('uk', 'UA')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KamiDropApp(startDiscovery: false));
    await tester.pump();
    expect(find.text('KamiDrop'), findsOneWidget);
    expect(find.text('Принтерів поки не видно'), findsOneWidget);
  });

  testWidgets('Будь-яка інша мова системи — англійська', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KamiDropApp(startDiscovery: false));
    await tester.pump();
    expect(find.text('No printers found yet'), findsOneWidget);
  });

  testWidgets('Мову можна вибрати вручну, і код без контексту теж її бачить', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('uk', 'UA')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KamiDropApp(startDiscovery: false));
    await tester.pump();
    appLanguage.value = 'en';
    await tester.pumpAndSettle();
    expect(find.text('No printers found yet'), findsOneWidget);
    expect(l10n.printerNotResponding, contains('isn\'t responding'), reason: 'глобальний l10n теж перемкнувся');
  });

  testWidgets('Файл з командного рядка (ПК) показується банером, як із «Поділитися»', (tester) async {
    await tester.pumpWidget(const KamiDropApp(startDiscovery: false, openFile: r'C:\Users\me\Docs\лист.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('лист.pdf'), findsOneWidget, reason: 'назва без шляху, і з Windows-розділювачами');
    expect(find.text('Pick a printer below'), findsOneWidget);
  });
}
