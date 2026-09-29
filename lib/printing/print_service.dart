import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../discovery/discovery.dart';
import 'compose.dart';
import 'sources.dart';
import 'test_page.dart';
import 'urf.dart';

enum PrintStage { preparing, rendering, sending, waiting, done, failed }

class PrintProgress {
  final PrintStage stage;
  final String message;
  final double? fraction;
  const PrintProgress(this.stage, this.message, {this.fraction});

  bool get finished => stage == PrintStage.done || stage == PrintStage.failed;
}

class PrintOptions {
  final bool color;
  final bool duplex;
  final int copies;
  const PrintOptions({this.color = false, this.duplex = false, this.copies = 1});
}

const _jobStates = {
  3: 'У черзі принтера',
  4: 'Утримується принтером',
  5: 'Друкується…',
  6: 'Принтер зупинився',
  7: 'Скасовано',
  8: 'Перервано принтером',
  9: 'Готово',
};

String _userName() => Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'kamidrop';

/// Вбудована тестова сторінка. Друга сторінка (BACK) потрібна лише для перевірки дуплексу.
Stream<PrintProgress> printTestPage(DiscoveredPrinter printer, PrintOptions options) async* {
  final caps = printer.capabilities;
  if (caps == null) {
    yield const PrintProgress(PrintStage.failed, 'Можливості принтера ще не відомі');
    return;
  }
  final color = options.color && caps.supportsColor;
  final duplex = options.duplex && caps.supportsDuplex;
  final info = '${caps.model} | URF ${caps.defaultDpi} dpi ${color ? 'sRGB' : 'sGray'} | '
      '${duplex ? 'two-sided-long-edge' : 'one-sided'} | sheet-back ${caps.sheetBack.name}';
  yield* printDocument(printer, TestPageSource(pageCount: duplex ? 2 : 1, color: color, info: info), options);
}

/// Повний конвеєр: рендер кожної сторінки → складання аркуша й URF (в ізоляті) → Print-Job → стеження.
/// Сторінки кодуються по одній, тож навіть великий PDF на 600 dpi не з'їдає всю пам'ять.
Stream<PrintProgress> printDocument(
  DiscoveredPrinter printer,
  PrintSource source,
  PrintOptions options, {
  List<int>? pages,
  LayoutOptions layout = const LayoutOptions(),
}) async* {
  final caps = printer.capabilities;
  if (caps == null) {
    yield const PrintProgress(PrintStage.failed, 'Можливості принтера ще не відомі');
    return;
  }
  if (!caps.supportsUrf) {
    yield const PrintProgress(PrintStage.failed, 'Принтер не приймає AirPrint-растр (image/urf)');
    return;
  }
  final selected = pages ?? List<int>.generate(source.pageCount, (i) => i);
  if (selected.isEmpty) {
    yield const PrintProgress(PrintStage.failed, 'Не вибрано жодної сторінки');
    return;
  }

  final dpi = caps.defaultDpi;
  final color = options.color && caps.supportsColor;
  final duplex = options.duplex && caps.supportsDuplex;
  final urfDuplex = duplex ? UrfDuplex.longEdge : UrfDuplex.none;
  final pageW = a4WidthPx(dpi), pageH = a4HeightPx(dpi);

  // Якщо принтер не вміє копії сам — повторюємо сторінки. При дуплексі з непарною кількістю
  // додаємо порожню, щоб кожна копія починалася з лицьового боку.
  final passes = caps.printerHandlesCopies ? 1 : options.copies;
  final padOdd = duplex && passes > 1 && selected.length.isOdd;

  final encoded = <Uint8List>[];
  try {
    for (var i = 0; i < selected.length; i++) {
      yield PrintProgress(
        PrintStage.rendering,
        'Готую сторінку ${i + 1} з ${selected.length}…',
        fraction: i / selected.length,
      );
      final lay = computeLayout(source.pageSize(selected[i]), layout, pageW: pageW, pageH: pageH, dpi: dpi);
      final px = await source.render(selected[i], width: lay.renderW, height: lay.renderH);
      encoded.add(await _encodeInIsolate(
        px,
        lay,
        pageW: pageW,
        pageH: pageH,
        dpi: dpi,
        color: color,
        back: duplex && i.isOdd ? caps.sheetBack : null,
        duplex: urfDuplex,
      ));
    }
    if (padOdd) {
      encoded.add(await _encodeBlankInIsolate(pageW: pageW, pageH: pageH, dpi: dpi, color: color, duplex: urfDuplex));
    }
  } catch (e) {
    yield PrintProgress(PrintStage.failed, 'Помилка підготовки: $e');
    return;
  }

  final doc = BytesBuilder(copy: false)..add(urfFileHeader(encoded.length * passes));
  for (var p = 0; p < passes; p++) {
    for (final e in encoded) {
      doc.add(e);
    }
  }
  final document = doc.takeBytes();

  yield PrintProgress(PrintStage.sending, 'Надсилаю ${(document.length / 1e6).toStringAsFixed(1)} МБ…');
  final client = printer.client();
  int? jobId;
  try {
    final r = await client.printJob(
      document: document,
      documentFormat: 'image/urf',
      jobName: source.name,
      userName: _userName(),
      keywords: {
        'sides': duplex ? 'two-sided-long-edge' : 'one-sided',
        'media': 'iso_a4_210x297mm',
        'print-color-mode': color ? 'color' : 'monochrome',
      },
      integers: {
        if (caps.printerHandlesCopies && options.copies > 1) 'copies': options.copies,
      },
    );
    if (!r.isSuccess) {
      final msg = r.first<String>('status-message');
      yield PrintProgress(PrintStage.failed, 'Принтер відхилив завдання (${r.statusHex}${msg != null ? ', $msg' : ''})');
      return;
    }
    jobId = r.first<int>('job-id');
  } catch (e) {
    yield PrintProgress(PrintStage.failed, '$e');
    return;
  }

  if (jobId == null) {
    yield const PrintProgress(PrintStage.done, 'Надіслано');
    return;
  }

  // Стежимо за завданням, поки принтер не скаже «готово».
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  String? last;
  while (DateTime.now().isBefore(deadline)) {
    int? state;
    try {
      state = (await client.getJobAttributes(jobId)).first<int>('job-state');
    } catch (_) {
      yield const PrintProgress(PrintStage.done, 'Надіслано (статус завдання недоступний)');
      return;
    }
    final text = _jobStates[state] ?? 'Стан: $state';
    if (state == 9) {
      yield const PrintProgress(PrintStage.done, 'Готово');
      return;
    }
    if (state == 7 || state == 8) {
      yield PrintProgress(PrintStage.failed, text);
      return;
    }
    if (text != last) {
      yield PrintProgress(PrintStage.waiting, text);
      last = text;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  yield const PrintProgress(PrintStage.done, 'Надіслано (принтер ще працює)');
}

// Окремі top-level функції: замикання для Isolate.run не повинні захоплювати контекст async*-генератора.

Future<Uint8List> _encodeInIsolate(
  SourcePixels px,
  PageLayout lay, {
  required int pageW,
  required int pageH,
  required int dpi,
  required bool color,
  required SheetBack? back,
  required UrfDuplex duplex,
}) {
  return Isolate.run(() {
    var page = composePage(px, lay, pageW: pageW, pageH: pageH, dpi: dpi, color: color);
    if (back != null) page = page.forBackSide(back, tumble: false);
    return encodeUrfPage(page, duplex: duplex);
  });
}

Future<Uint8List> _encodeBlankInIsolate({
  required int pageW,
  required int pageH,
  required int dpi,
  required bool color,
  required UrfDuplex duplex,
}) {
  return Isolate.run(() {
    final size = pageW * pageH * (color ? 3 : 1);
    final page = UrfPage(
      width: pageW,
      height: pageH,
      dpi: dpi,
      color: color,
      pixels: Uint8List(size)..fillRange(0, size, 0xff),
    );
    return encodeUrfPage(page, duplex: duplex);
  });
}
