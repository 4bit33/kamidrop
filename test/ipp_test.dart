import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/ipp/ipp.dart';
import 'package:kamidrop/printing/capabilities.dart';
import 'package:kamidrop/printing/urf.dart';

Uint8List _fakeBrotherResponse() {
  final b = IppRequestBuilder(0x0000) // статус successful-ok на місці operation-id
    ..group(IppTag.operationAttributes)
    ..string(IppTag.charset, 'attributes-charset', 'utf-8')
    ..group(IppTag.printerAttributes)
    ..string(IppTag.text, 'printer-make-and-model', 'Brother DCP-J572DW')
    ..integer('printer-state', 3, tag: IppTag.enumValue)
    ..strings(IppTag.mimeType, 'document-format-supported', ['image/urf', 'image/jpeg'])
    ..strings(IppTag.keyword, 'urf-supported', ['SRGB24', 'W8', 'RS300', 'DM3'])
    ..strings(IppTag.keyword, 'sides-supported', ['one-sided', 'two-sided-long-edge'])
    ..strings(IppTag.keyword, 'print-color-mode-supported', ['auto', 'color', 'monochrome'])
    ..attr(IppTag.begCollection, 'media-col-ready', [])
    ..attr(0x4A, '', 'media-size'.codeUnits)
    ..attr(IppTag.begCollection, '', [])
    ..attr(IppTag.endCollection, '', [])
    ..attr(IppTag.endCollection, '', [])
    ..attr(IppTag.rangeOfInteger, 'copies-supported', [0, 0, 0, 1, 0, 0, 0, 99])
    ..strings(IppTag.keyword, 'job-creation-attributes-supported', ['copies', 'sides'])
    ..strings(IppTag.name, 'marker-names', ['M', 'BK'])
    ..strings(IppTag.name, 'marker-colors', ['#FF00FF', '#000000'])
    ..integer('marker-levels', 50)
    ..integer('', 81)
    // Як у справжнього Brother: 0 — без полів, 300 — звичайні 3 мм, 1200 — для інших носіїв.
    ..integer('media-top-margin-supported', 300)
    ..integer('', 0)
    ..integer('', 1200)
    ..integer('media-left-margin-supported', 300)
    ..integer('', 0);
  return b.build();
}

void main() {
  test('Запит Get-Printer-Attributes розбирається назад', () {
    final req = (IppRequestBuilder.standard(IppOp.getPrinterAttributes, 'ipp://1.2.3.4:631/ipp/print')
          ..string(IppTag.keyword, 'requested-attributes', 'all'))
        .build();
    expect(req[0], 2);
    expect(req[3], 0x0B);
    final parsed = parseIppResponse(req);
    expect(parsed.first<String>('printer-uri'), 'ipp://1.2.3.4:631/ipp/print');
    expect(parsed.first<String>('requested-attributes'), 'all');
  });

  test('Відповідь принтера -> можливості', () {
    final r = parseIppResponse(_fakeBrotherResponse());
    expect(r.isSuccess, isTrue);
    expect(r['media-col-ready'].length, 1);
    final caps = PrinterCapabilities.fromIpp(r, txt: {'copies': 'F'});
    expect(caps.model, 'Brother DCP-J572DW');
    expect(caps.supportsUrf, isTrue);
    expect(caps.supportsColor, isTrue);
    expect(caps.supportsDuplex, isTrue);
    expect(caps.defaultDpi, 300);
    expect(caps.sheetBack, SheetBack.rotated);
    expect(caps.printerHandlesCopies, isFalse, reason: 'TXT copies=F');
    expect(caps.maxCopies, 99);
    expect(caps.markers.map((m) => m.level), [50, 81]);
  });

  test('Поля принтера: найменше ненульове значення, у мм', () {
    final caps = PrinterCapabilities.fromIpp(parseIppResponse(_fakeBrotherResponse()));
    expect(caps.margins.top, 3.0);
    expect(caps.margins.left, 3.0);
    expect(caps.margins.bottom, 0, reason: 'атрибута немає — поле невідоме');
  });
}
