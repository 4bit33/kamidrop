import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/main.dart';

void main() {
  testWidgets('Головний екран показує назву й порожній стан', (tester) async {
    await tester.pumpWidget(const KamiDropApp(startDiscovery: false));
    await tester.pump();
    expect(find.text('KamiDrop'), findsOneWidget);
    expect(find.text('Принтерів поки не видно'), findsOneWidget);
  });
}
