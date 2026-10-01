import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/scan/escl.dart';

/// Фейковий eSCL-сканер: перший NextDocument — 503 (ще сканує), далі сторінка, далі 404.
class _FakeScanner {
  _FakeScanner({this.postStatus = 201, this.docStatus = 200});
  final int postStatus, docStatus;
  final log = <String>[];
  String? postedBody;
  bool? chunked;
  late final HttpServer server;
  var _next = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      log.add('${req.method} ${req.uri.path}');
      final body = await req.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      if (req.method == 'POST') {
        chunked = req.headers.chunkedTransferEncoding;
        postedBody = String.fromCharCodes(body.takeBytes());
        req.response.statusCode = postStatus;
        if (postStatus == 201) req.response.headers.set('Location', 'http://127.0.0.1:${server.port}/eSCL/ScanJobs/42');
      } else if (req.uri.path.endsWith('NextDocument')) {
        final n = _next++;
        req.response.statusCode = n == 0 ? 503 : (n == 1 ? docStatus : 404);
        if (n == 1 && docStatus == 200) req.response.add([0xFF, 0xD8, 0xFF, 0xD9]);
      }
      await req.response.close();
    });
  }
}

void main() {
  test('Можливості Brother DCP-J572DW', () {
    final caps = ScannerCaps.parse(File('test/fixtures/escl_caps_brother_dcp_j572dw.xml').readAsStringSync());
    expect(caps.model, 'Brother DCP-J572DW');
    expect(caps.colorModes, containsAll(['RGB24', 'Grayscale8', 'BlackAndWhite1']));
    expect(caps.resolutions, [100, 200, 300, 600]);
    expect(caps.supportsJpeg, isTrue);
    expect(caps.platen, isTrue);
    expect(caps.adf, isFalse);
    expect([caps.maxWidth, caps.maxHeight], [2550, 3507]);
  });

  test('XML налаштувань — одним рядком, без відступів (Brother інакше ігнорує)', () {
    final xml = scanSettingsXml(colorMode: 'Grayscale8', dpi: 100, widthUnits: 2480, heightUnits: 3507);
    expect(xml.contains('\n'), isFalse);
    expect(RegExp(r'>\s+<').hasMatch(xml), isFalse);
    expect(xml, contains('<scan:ColorMode>Grayscale8</scan:ColorMode>'));
    expect(xml, contains('<scan:XResolution>100</scan:XResolution>'));
    expect(xml.startsWith('<?xml'), isFalse);
  });

  test('Сканування: чекає, поки сканер готовий, і закриває завдання', () async {
    final fake = _FakeScanner();
    await fake.start();
    final data = await EsclClient(host: '127.0.0.1', port: fake.server.port).scanPage('<x/>');
    expect(data, [0xFF, 0xD8, 0xFF, 0xD9]);
    expect(fake.chunked, isFalse, reason: 'Brother не приймає chunked — тільки з Content-Length');
    expect(fake.log, [
      'POST /eSCL/ScanJobs',
      'GET /eSCL/ScanJobs/42/NextDocument', // 503
      'GET /eSCL/ScanJobs/42/NextDocument', // сторінка
      'GET /eSCL/ScanJobs/42/NextDocument', // 404 — завдання закрите
    ]);
    await fake.server.close(force: true);
  });

  test('Помилка сторінки — завдання видаляється', () async {
    final fake = _FakeScanner(docStatus: 500);
    await fake.start();
    await expectLater(EsclClient(host: '127.0.0.1', port: fake.server.port).scanPage('<x/>'),
        throwsA(isA<ScanException>()));
    expect(fake.log.last, 'DELETE /eSCL/ScanJobs/42');
    await fake.server.close(force: true);
  });

  test('Непідтримувані налаштування — зрозуміла помилка', () async {
    final fake = _FakeScanner(postStatus: 409);
    await fake.start();
    await expectLater(EsclClient(host: '127.0.0.1', port: fake.server.port).scanPage('<x/>'),
        throwsA(isA<ScanException>().having((e) => e.message, 'message', contains('не підтримує'))));
    await fake.server.close(force: true);
  });
}
