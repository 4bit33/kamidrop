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
import '../l10n/l10n.dart';

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

PrintProgress get _cancelledBeforeSend => PrintProgress(PrintStage.cancelled, l10n.cancelledBeforeSend);

class PrintOptions {
  final bool color;
  final bool duplex;
  final int copies;
  const PrintOptions({this.color = false, this.duplex = false, this.copies = 1});
}

Map<int, String> get _jobStates => {
  3: l10n.jobPending,
  4: l10n.jobHeld,
  5: l10n.jobProcessing,
  6: l10n.jobStopped,
  7: l10n.jobCanceled,
  8: l10n.jobAborted,
  9: l10n.done,
};

String _userName() => Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'kamidrop';

/// Вбудована тестова сторінка. Друга сторінка (BACK) потрібна лише для перевірки дуплексу.
Stream<PrintProgress> printTestPage(DiscoveredPrinter printer, PrintOptions options, {PrintCancel? cancel}) async* {
  final caps = printer.capabilities;
  if (caps == null) {
    yield PrintProgress(PrintStage.failed, l10n.capsUnknownYet);
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
    yield PrintProgress(PrintStage.failed, l10n.capsUnknownYet);
    return;
  }
  if (!caps.supportsUrf) {
    yield PrintProgress(PrintStage.failed, l10n.noUrf);
    return;
  }
  final selected = pages ?? List<int>.generate(source.pageCount, (i) => i);
  if (selected.isEmpty) {
    yield PrintProgress(PrintStage.failed, l10n.noPagesSelected);
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
        l10n.preparingPage(i + 1, selected.length),
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
    yield PrintProgress(PrintStage.failed, l10n.prepareError('$e'));
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
  yield PrintProgress(PrintStage.sending, l10n.sendingMb(decimal(document.length / 1e6, 1)));
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
      yield PrintProgress(PrintStage.failed, l10n.printerRejected('${r.statusHex}${msg != null ? ', $msg' : ''}'));
      return;
    }
    jobId = r.first<int>('job-id');
  } catch (e) {
    yield PrintProgress(PrintStage.failed, '$e');
    return;
  }

  if (jobId == null) {
    yield PrintProgress(PrintStage.done, l10n.sent);
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
      yield PrintProgress(PrintStage.waiting, l10n.cancelling);
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
          if (last != _silentText) yield PrintProgress(PrintStage.waiting, _silentText);
          last = _silentText;
          await _pause(const Duration(seconds: 3), cancelled);
          continue;
        }
      }
      if (await _restartedSince(client, sentAt)) {
        yield PrintProgress(PrintStage.failed, l10n.rebootedDuringPrint);
      } else if (r == null) {
        yield PrintProgress(PrintStage.done, l10n.stoppedResponding);
      } else {
        yield PrintProgress(PrintStage.done, l10n.sentNoStatus);
      }
      return;
    }
    silentSince = null;
    final text = _jobStates[state] ?? l10n.jobState('$state');
    if (state == 9) {
      yield PrintProgress(PrintStage.done, l10n.done);
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
  yield PrintProgress(PrintStage.done, l10n.sentStillPrinting);
}

String get _silentText => l10n.printerSilentWaiting;

/// Пауза між опитуваннями, що обривається натисканням «Скасувати».
Future<void> _pause(Duration d, Future<bool> cancelled) => Future.any([Future<bool>.delayed(d, () => false), cancelled]);

Future<PrintProgress> _cancelJob(IppClient client, int jobId) async {
  try {
    final r = await client.cancelJob(jobId, userName: _userName());
    if (r.isSuccess) {
      return PrintProgress(PrintStage.cancelled, l10n.jobCancelledMayPrint);
    }
    // 0x0507 — job-not-cancelable: принтер уже все зробив або завдання вже скасоване.
    if (r.status == 0x0507) {
      return PrintProgress(PrintStage.failed, l10n.tooLateToCancel);
    }
    final msg = r.first<String>('status-message');
    return PrintProgress(PrintStage.failed, l10n.printerDidNotCancel('${r.statusHex}${msg != null ? ', $msg' : ''}'));
  } catch (e) {
    return PrintProgress(PrintStage.failed, l10n.cancelFailed('$e'));
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
