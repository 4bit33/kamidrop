import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../discovery/discovery.dart';
import '../ipp/ipp.dart';
import '../ipp/ipp_client.dart';
import 'compose.dart';
import 'sources.dart';
import 'test_page.dart';
import 'urf.dart';

enum PrintStage { preparing, rendering, sending, waiting, done, failed, cancelled }

class PrintProgress {
  final PrintStage stage;
  final String message;
  final double? fraction;
  const PrintProgress(this.stage, this.message, {this.fraction});

  bool get finished => stage == PrintStage.done || stage == PrintStage.failed || stage == PrintStage.cancelled;
}

/// Кнопка «Скасувати»: друк перевіряє її між сторінками, після надсилання й під час очікування.
class PrintCancel {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Завершується в момент скасування — щоб не чекати чергового опитування принтера.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

const _cancelledBeforeSend = PrintProgress(PrintStage.cancelled, 'Скасовано — на принтер нічого не надіслано');

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
Stream<PrintProgress> printTestPage(DiscoveredPrinter printer, PrintOptions options, {PrintCancel? cancel}) async* {
  final caps = printer.capabilities;
  if (caps == null) {
    yield const PrintProgress(PrintStage.failed, 'Можливості принтера ще не відомі');
    return;
  }
  final color = options.color && caps.supportsColor;
  final duplex = options.duplex && caps.supportsDuplex;
  final info = '${caps.model} | URF ${caps.defaultDpi} dpi ${color ? 'sRGB' : 'sGray'} | '
      '${duplex ? 'two-sided-long-edge' : 'one-sided'} | sheet-back ${caps.sheetBack.name}';
  yield* printDocument(printer, TestPageSource(pageCount: duplex ? 2 : 1, color: color, info: info), options,
      cancel: cancel);
}

/// Повний конвеєр: рендер кожної сторінки → складання аркуша й URF (в ізоляті) → Print-Job → стеження.
/// Сторінки кодуються по одній, тож навіть великий PDF на 600 dpi не з'їдає всю пам'ять.
Stream<PrintProgress> printDocument(
  DiscoveredPrinter printer,
  PrintSource source,
  PrintOptions options, {
  List<int>? pages,
  LayoutOptions layout = const LayoutOptions(),
  PrintCancel? cancel,
}) async* {
  cancel ??= PrintCancel();
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
  final borderless = layout.borderless && caps.supportsBorderless;
  final margins = effectiveMargins(layout, caps.margins, printerBorderless: caps.supportsBorderless);

  // Якщо принтер не вміє копії сам — повторюємо сторінки. При дуплексі з непарною кількістю
  // додаємо порожню, щоб кожна копія починалася з лицьового боку.
  final passes = caps.printerHandlesCopies ? 1 : options.copies;
  final padOdd = duplex && passes > 1 && selected.length.isOdd;

  final encoded = <Uint8List>[];
  try {
    for (var i = 0; i < selected.length; i++) {
      if (cancel.isCancelled) {
        yield _cancelledBeforeSend;
        return;
      }
      yield PrintProgress(
        PrintStage.rendering,
        'Готую сторінку ${i + 1} з ${selected.length}…',
        fraction: i / selected.length,
      );
      final lay = computeLayout(source.pageSize(selected[i]), layout,
          pageW: pageW, pageH: pageH, dpi: dpi, printerMargins: margins);
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

  if (cancel.isCancelled) {
    yield _cancelledBeforeSend;
    return;
  }
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
        if (!borderless) 'media': 'iso_a4_210x297mm',
        'print-color-mode': color ? 'color' : 'monochrome',
      },
      integers: {
        if (caps.printerHandlesCopies && options.copies > 1) 'copies': options.copies,
      },
      // «До краю»: A4 з нульовими полями — так само робить AirPrint.
      collections: {
        if (borderless)
          'media-col': {
            'media-size': {'x-dimension': 21000, 'y-dimension': 29700},
            'media-top-margin': 0,
            'media-bottom-margin': 0,
            'media-left-margin': 0,
            'media-right-margin': 0,
          },
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
  final sentAt = DateTime.now();
  final cancelled = cancel.whenCancelled.then((_) => true);
  final deadline = sentAt.add(const Duration(minutes: 5));
  DateTime? silentSince; // коли принтер перестав відповідати
  String? last;
  while (DateTime.now().isBefore(deadline)) {
    if (cancel.isCancelled) {
      yield const PrintProgress(PrintStage.waiting, 'Скасовую…');
      yield await _cancelJob(client, jobId);
      return;
    }
    IppResponse? r;
    try {
      r = await client.getJobAttributes(jobId);
    } catch (_) {}
    final state = r != null && r.isSuccess ? r.first<int>('job-state') : null;
    if (state == null) {
      // Мовчить або забув завдання — можливо, перезавантажився. Чекаємо до 2 хв, поки оживе.
      if (r == null) {
        silentSince ??= DateTime.now();
        if (DateTime.now().difference(silentSince) < const Duration(minutes: 2)) {
          if (last != _silentText) yield const PrintProgress(PrintStage.waiting, _silentText);
          last = _silentText;
          await _pause(const Duration(seconds: 3), cancelled);
          continue;
        }
      }
      if (await _restartedSince(client, sentAt)) {
        yield const PrintProgress(
            PrintStage.failed, 'Принтер перезавантажився під час друку — завдання, найпевніше, втрачено');
      } else if (r == null) {
        yield const PrintProgress(PrintStage.done, 'Принтер перестав відповідати — перевір, чи надрукувалось');
      } else {
        yield const PrintProgress(PrintStage.done, 'Надіслано (статус завдання недоступний)');
      }
      return;
    }
    silentSince = null;
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
    await _pause(const Duration(seconds: 2), cancelled);
  }
  yield const PrintProgress(PrintStage.done, 'Надіслано (принтер ще працює)');
}

const _silentText = 'Принтер не відповідає, чекаю…';

/// Пауза між опитуваннями, що обривається натисканням «Скасувати».
Future<void> _pause(Duration d, Future<bool> cancelled) => Future.any([Future<bool>.delayed(d, () => false), cancelled]);

Future<PrintProgress> _cancelJob(IppClient client, int jobId) async {
  try {
    final r = await client.cancelJob(jobId, userName: _userName());
    if (r.isSuccess) {
      return const PrintProgress(PrintStage.cancelled, 'Завдання скасовано. Аркуш, що вже друкувався, може вийти');
    }
    // 0x0507 — job-not-cancelable: принтер уже все зробив або завдання вже скасоване.
    if (r.status == 0x0507) {
      return const PrintProgress(PrintStage.failed, 'Запізно — принтер уже завершив це завдання');
    }
    final msg = r.first<String>('status-message');
    return PrintProgress(PrintStage.failed, 'Принтер не скасував завдання (${r.statusHex}${msg != null ? ', $msg' : ''})');
  } catch (e) {
    return PrintProgress(PrintStage.failed, 'Не вдалося скасувати: $e');
  }
}

/// Чи перезавантажився принтер після [since]: його printer-up-time менший за час, що минув.
Future<bool> _restartedSince(IppClient client, DateTime since) async {
  try {
    final up = (await client.getPrinterAttributes()).first<int>('printer-up-time');
    return up != null && up < DateTime.now().difference(since).inSeconds;
  } catch (_) {
    return false;
  }
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
