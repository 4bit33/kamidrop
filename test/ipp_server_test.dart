import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/ipp/ipp.dart';
import 'package:kamidrop/printproxy/ipp_server.dart';

void main() {
  const uri = 'ipp://localhost:8631/ipp/print/x';
  IppRequestBuilder req(int op) => IppRequestBuilder.standard(op, uri, requestId: 7);

  test('proxySlug лишає тільки безпечні символи', () {
    expect(proxySlug('urn:uuid:ab-12 Ї'), 'urn-uuid-ab-12-');
  });

  test('Можливості: PDF, колір і дуплекс зі справжнього принтера; без принтера — зупинений', () async {
    final s = IppProxyServer(
      printers: () => const [ProxyPrinter(slug: 'x', name: 'Тест', color: true, duplex: true, dpi: 600, margin: 440)],
      onJob: (_) async => true,
    );
    final r = parseIppResponse(await s.handle('x', req(IppOp.getPrinterAttributes).build()));
    expect(r.isSuccess, isTrue);
    expect(r['document-format-supported'], ['application/pdf']);
    expect(r['sides-supported'], contains('two-sided-long-edge'));
    expect(r['print-color-mode-supported'], contains('color'));
    expect('${r.first<IppResolution>('printer-resolution-default')}', '600x600dpi');
    expect(r.first<int>('media-top-margin-supported'), 440);
    expect(r.first<int>('printer-state'), 3);
    expect(r.first<String>('printer-uuid'), matches(RegExp(r'^urn:uuid:[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')));
    expect(proxyUuid('x'), isNot(proxyUuid('y')));

    final gone = parseIppResponse(await s.handle('nema', req(IppOp.getPrinterAttributes).build()));
    expect(gone.first<int>('printer-state'), 5);
  });

  test('Create-Job + Send-Document, як у Windows: налаштування з першого, PDF з другого', () async {
    final got = Completer<ProxyJob>();
    final finish = Completer<bool>();
    late Uint8List saved;
    final s = IppProxyServer(
      printers: () => const [ProxyPrinter(slug: 'x', name: 'Тест')],
      onJob: (j) {
        saved = File(j.path).readAsBytesSync();
        got.complete(j);
        return finish.future;
      },
    );
    final create = req(IppOp.createJob)
      ..string(IppTag.name, 'job-name', 'Заява')
      ..group(IppTag.jobAttributes)
      ..integer('copies', 3)
      ..string(IppTag.keyword, 'sides', 'two-sided-long-edge')
      ..string(IppTag.keyword, 'print-color-mode', 'monochrome');
    final id = parseIppResponse(await s.handle('x', create.build())).first<int>('job-id')!;

    final send = req(IppOp.sendDocument)..integer('job-id', id);
    final sent = parseIppResponse(await s.handle('x', send.build(document: utf8.encode('%PDF-1.7 тест'))));
    expect(sent.first<int>('job-state'), 5, reason: 'друкується');

    final job = await got.future;
    expect(utf8.decode(saved), '%PDF-1.7 тест');
    expect([job.name, job.copies, job.duplex, job.color], ['Заява', 3, true, false]);

    Future<int?> state() async =>
        parseIppResponse(await s.handle('x', (req(IppOp.getJobAttributes)..integer('job-id', id)).build()))
            .first<int>('job-state');
    expect(await state(), 5);
    finish.complete(false);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100)); // видалення тимчасового файла
    expect(await state(), 8, reason: 'друк не вдався — завдання перерване');
    expect(File(job.path).existsSync(), isFalse);
  });
}
