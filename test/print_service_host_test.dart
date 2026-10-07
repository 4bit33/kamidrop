import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/discovery/discovery.dart';
import 'package:kamidrop/printing/capabilities.dart';
import 'package:kamidrop/printing/compose.dart';
import 'package:kamidrop/printing/urf.dart';
import 'package:kamidrop/printservice/print_service_host.dart';

void main() {
  test('Сторінки: «усі», або PDF уже містить лише вибрані, або вибираємо самі', () {
    expect(selectPages([], 3), [0, 1, 2]);
    expect(selectPages([(0, 0x7fffffff)], 3), [0, 1, 2], reason: 'PageRange.ALL_PAGES');
    expect(selectPages([(1, 2)], 2), [0, 1], reason: 'застосунок записав у PDF лише сторінки 2–3');
    expect(selectPages([(1, 2), (4, 4)], 6), [1, 2, 4]);
    expect(selectPages([(5, 9)], 3), [0, 1, 2], reason: 'за межами документа — друкуємо все');
  });

  test('Принтер для системного діалогу: можливості й поля', () {
    final p = DiscoveredPrinter(
      id: 'uuid-1',
      name: 'Brother',
      host: '10.0.0.5',
      port: 631,
      path: 'ipp/print',
      tls: false,
      txt: const {},
      lastSeen: DateTime.now(),
    );
    expect(printerInfoMap(p)['ready'], isFalse, reason: 'можливості ще не відомі');
    p.capabilities = const PrinterCapabilities(
      model: 'Brother DCP-J572DW',
      state: PrinterState.idle,
      stateMessage: null,
      formats: ['image/urf'],
      urf: ['SRGB24', 'RS300'],
      urfResolutions: [300],
      supportsColor: true,
      supportsDuplex: true,
      supportsLandscape: true,
      sheetBack: SheetBack.rotated,
      printerHandlesCopies: false,
      maxCopies: 99,
      media: [],
      markers: [],
      margins: SheetMargins.all(3),
    );
    final m = printerInfoMap(p);
    expect([m['ready'], m['color'], m['duplex'], m['dpi']], [true, true, true, 300]);
    expect((m['margins'] as Map)['left'], 3);
  });
}
