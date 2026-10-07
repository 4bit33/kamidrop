import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/scan/escl.dart';

/// Фейковий eSCL-сканер: перший NextDocument — 503 (ще сканує), далі сторінка, далі 404.
class _FakeScanner {
  _FakeScanner({this.postStatus = 201, this.docStatus = 200, this.pages = 1});
  final int postStatus, docStatus, pages;
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
        final n = _next++; // 0 — ще сканує, 1..pages — сторінки, далі 404
        final page = n >= 1 && n <= pages;
        req.response.statusCode = n == 0 ? 503 : (page ? docStatus : 404);
        if (page && docStatus == 200) req.response.add([0xFF, 0xD8, n, 0xFF, 0xD9]);
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
    final pages = await EsclClient(host: '127.0.0.1', port: fake.server.port).scan('<x/>');
    expect(pages, [
      [0xFF, 0xD8, 1, 0xFF, 0xD9]
    ]);
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
    await expectLater(EsclClient(host: '127.0.0.1', port: fake.server.port).scan('<x/>'),
        throwsA(isA<ScanException>()));
    expect(fake.log.last, 'DELETE /eSCL/ScanJobs/42');
    await fake.server.close(force: true);
  });

  test('Непідтримувані налаштування — зрозуміла помилка', () async {
    final fake = _FakeScanner(postStatus: 409);
    await fake.start();
    await expectLater(EsclClient(host: '127.0.0.1', port: fake.server.port).scan('<x/>'),
        throwsA(isA<ScanException>().having((e) => e.message, 'message', contains('не підтримує'))));
    await fake.server.close(force: true);
  });

  test('Подавач: усі аркуші одним завданням, корінь шляху з mDNS', () async {
    final fake = _FakeScanner(pages: 3);
    await fake.start();
    final seen = <int>[];
    final pages =
        await EsclClient(host: '127.0.0.1', port: fake.server.port, root: '/eSCL/').scan('<x/>', onPage: seen.add);
    expect(pages.map((p) => p[2]), [1, 2, 3]);
    expect(seen, [1, 2, 3]);
    expect(fake.log.where((l) => l.endsWith('NextDocument')).length, 5, reason: '503, 3 сторінки, 404');
    await fake.server.close(force: true);
  });

  test('Порожній подавач (одразу 404) — зрозуміла помилка', () async {
    final fake = _FakeScanner(pages: 0);
    await fake.start();
    await expectLater(EsclClient(host: '127.0.0.1', port: fake.server.port).scan('<x/>'),
        throwsA(isA<ScanException>().having((e) => e.message, 'message', contains('нема паперу'))));
    await fake.server.close(force: true);
  });

  test('Сканер шлюзу (WSD …) прив\'язується до свого принтера, а не до чужого', () {
    bool m(String scanner, String host, String printer, String phost) => scannerMatchesPrinter(
        scannerName: scanner, scannerHost: host, printerName: printer, printerHost: phost);
    const xeroxScan = 'WSD Xerox WorkCentre 3225 (XRX000000000000)';
    expect(m(xeroxScan, '10.0.0.224', 'Xerox WorkCentre 3225 (XRX000000000000)', '10.0.0.78'), isTrue);
    expect(m(xeroxScan, '10.0.0.224', 'Brother DCP-J572DW', '10.0.0.114'), isFalse);
    expect(m('Brother DCP-J572DW', '10.0.0.114', 'Brother DCP-J572DW', '10.0.0.114'), isTrue, reason: 'та сама адреса');
    expect(m('HP', '10.0.0.5', 'HP LaserJet', '10.0.0.6'), isFalse, reason: 'надто коротка назва — не вгадуємо');
  });

  test('Можливості шлюзу AirSane (Xerox через WSD): скло й подавач, 75–300 dpi', () {
    final caps = ScannerCaps.parse(File('test/fixtures/escl_caps_airsane_xerox3225.xml').readAsStringSync());
    expect(caps.platen, isTrue);
    expect(caps.adf, isTrue);
    expect(caps.resolutions, [75, 100, 150, 200, 300]);
    expect(caps.colorModes, containsAll(['RGB24', 'Grayscale8']));
  });
}
