import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/discovery/discovery.dart';
import 'package:kamidrop/ipp/ipp.dart';
import 'package:kamidrop/printing/capabilities.dart';
import 'package:kamidrop/printing/compose.dart';
import 'package:kamidrop/printing/print_service.dart';
import 'package:kamidrop/printing/sources.dart';
import 'package:kamidrop/printing/urf.dart';

/// Біла сторінка без dart:ui.
class _BlankSource extends PrintSource {
  _BlankSource(this.pageCount);

  @override
  final int pageCount;
  @override
  String get name => 'test';
  @override
  bool get isDocument => true;
  @override
  ContentSize pageSize(int index) => const ContentSize(210, 297);
  @override
  Future<SourcePixels> render(int index, {required int width, required int height}) async => SourcePixels(
        data: Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255),
        width: width,
        height: height,
        order: PixelOrder.rgba,
      );
}

/// Фейковий IPP-принтер: приймає завдання, каже «друкується», відповідає на Cancel-Job.
class _FakePrinter {
  _FakePrinter({this.cancelStatus = 0x0000});

  final int cancelStatus;
  final ops = <int>[];
  final bodies = <Uint8List>[];
  late final HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await req.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      final data = body.takeBytes();
      final op = data[2] << 8 | data[3];
      ops.add(op);
      bodies.add(data);
      final status = op == IppOp.cancelJob ? cancelStatus : 0x0000;
      final b = IppRequestBuilder(status) // статус на місці operation-id
        ..group(IppTag.operationAttributes)
        ..string(IppTag.charset, 'attributes-charset', 'utf-8')
        ..group(IppTag.jobAttributes)
        ..integer('job-id', 7)
        ..integer('job-state', 5, tag: IppTag.enumValue); // друкується
      req.response.headers.contentType = ContentType('application', 'ipp');
      req.response.add(b.build());
      await req.response.close();
    });
  }

  DiscoveredPrinter printer({bool borderless = false}) => DiscoveredPrinter(
        id: 'fake',
        name: 'Fake',
        host: '127.0.0.1',
        port: server.port,
        path: 'ipp/print',
        tls: false,
        txt: const {},
        lastSeen: DateTime.now(),
      )..capabilities = PrinterCapabilities(
          model: 'Fake',
          state: PrinterState.idle,
          stateMessage: null,
          formats: ['image/urf'],
          urf: ['W8', 'RS75'],
          urfResolutions: [75],
          supportsColor: false,
          supportsDuplex: false,
          supportsLandscape: false,
          sheetBack: SheetBack.normal,
          printerHandlesCopies: true,
          maxCopies: 1,
          media: [],
          markers: [],
          supportsBorderless: borderless,
        );
}

void main() {
  test('Скасування до надсилання: на принтер нічого не йде', () async {
    final fake = _FakePrinter();
    await fake.start();
    final cancel = PrintCancel()..cancel();
    final last = await printDocument(fake.printer(), _BlankSource(3), const PrintOptions(), cancel: cancel).last;
    expect(last.stage, PrintStage.cancelled);
    expect(fake.ops, isEmpty);
    await fake.server.close(force: true);
  });

  test('Скасування під час друку: Cancel-Job, без чекання опитування', () async {
    final fake = _FakePrinter();
    await fake.start();
    final cancel = PrintCancel();
    final stages = <PrintProgress>[];
    await for (final p in printDocument(fake.printer(), _BlankSource(1), const PrintOptions(), cancel: cancel)) {
      stages.add(p);
      if (p.stage == PrintStage.waiting && p.message == 'Друкується…') cancel.cancel();
    }
    expect(stages.last.stage, PrintStage.cancelled);
    expect(fake.ops, [IppOp.printJob, IppOp.getJobAttributes, IppOp.cancelJob]);
    await fake.server.close(force: true);
  });

  test('Запізно скасовувати: принтер уже завершив завдання', () async {
    final fake = _FakePrinter(cancelStatus: 0x0507);
    await fake.start();
    final cancel = PrintCancel();
    final stages = <PrintProgress>[];
    await for (final p in printDocument(fake.printer(), _BlankSource(1), const PrintOptions(), cancel: cancel)) {
      stages.add(p);
      if (p.stage == PrintStage.waiting && p.message == 'Друкується…') cancel.cancel();
    }
    expect(stages.last.stage, PrintStage.failed);
    expect(stages.last.message, contains('Запізно'));
    await fake.server.close(force: true);
  });

  test('«До краю»: media-col з нульовими полями замість media — лише якщо принтер уміє', () async {
    for (final canBorderless in [true, false]) {
      final fake = _FakePrinter();
      await fake.start();
      final cancel = PrintCancel();
      await for (final p in printDocument(fake.printer(borderless: canBorderless), _BlankSource(1),
          const PrintOptions(), layout: const LayoutOptions(borderless: true), cancel: cancel)) {
        if (p.stage == PrintStage.waiting) cancel.cancel();
      }
      final job = fake.bodies.first;
      final header = String.fromCharCodes(job.sublist(0, job.length.clamp(0, 600)));
      expect(header.contains('media-col'), canBorderless);
      expect(header.contains('media-top-margin'), canBorderless);
      expect(header.contains('iso_a4_210x297mm'), !canBorderless);
      await fake.server.close(force: true);
    }
  });
}
