// Служба друку Android: Dart-бік. Нативна служба (KamiPrintService.kt) запускає цей код у
// фоновому Flutter без вікна; ми шукаємо принтери тим самим PrinterDiscovery, що й застосунок,
// і друкуємо PDF від системи тим самим конвеєром (printDocument).
//
// Канал `kamidrop/printservice`:
//   Dart → служба: printers(List<Map>), jobState({jobId, state, message})
//   служба → Dart: print({jobId, printerId, path, copies, color, duplex, ranges}), cancel(jobId), refresh()
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../discovery/discovery.dart';
import '../l10n/l10n.dart';
import '../printing/compose.dart';
import '../printing/print_service.dart';
import '../printing/sources.dart';
import '../settings.dart';

/// Принтер для системного діалогу друку. Поля — у мм (нативний бік переводить у тисячні дюйма).
Map<String, Object?> printerInfoMap(DiscoveredPrinter p) {
  final caps = p.capabilities;
  return {
    'id': p.id,
    'name': p.name,
    'model': caps?.model,
    'ready': caps != null && caps.supportsUrf,
    'color': caps?.supportsColor ?? false,
    'duplex': caps?.supportsDuplex ?? false,
    'dpi': caps?.defaultDpi ?? 300,
    'margins': caps == null
        ? null
        : {
            'top': caps.margins.top,
            'bottom': caps.margins.bottom,
            'left': caps.margins.left,
            'right': caps.margins.right,
          },
  };
}

/// Які сторінки PDF друкувати. [ranges] — пари (з, по) від системи, з нуля, включно; порожньо або
/// «усі» (по = 2147483647) — усі сторінки. Застосунки часто вже записують у PDF лише вибрані
/// сторінки — тоді кількість збігається, і друкуємо весь файл.
List<int> selectPages(List<(int, int)> ranges, int docPages) {
  final all = List<int>.generate(docPages, (i) => i);
  if (ranges.isEmpty || ranges.any((r) => r.$1 <= 0 && r.$2 >= 0x7fffffff)) return all;
  final count = ranges.fold<int>(0, (n, r) => n + r.$2 - r.$1 + 1);
  if (count == docPages) return all;
  final pages = <int>{
    for (final (from, to) in ranges)
      for (var i = from; i <= to && i < docPages; i++) i,
  }.toList()
    ..sort();
  return pages.isEmpty ? all : pages;
}

class PrintServiceHost {
  static const _channel = MethodChannel('kamidrop/printservice');

  final discovery = PrinterDiscovery();
  final _jobs = <String, PrintCancel>{};

  Future<void> start() async {
    final settings = await KamiSettings.load();
    final lang = settings.language;
    setL10n(lookupL10n(lang == 'system' ? resolveAppLocale(ui.PlatformDispatcher.instance.locale) : ui.Locale(lang)));
    _channel.setMethodCallHandler(_onCall);
    discovery.addListener(_report);
    discovery.start();
    _report();
  }

  void _report() {
    _channel.invokeMethod('printers', [for (final p in discovery.printers) printerInfoMap(p)]);
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'print':
        unawaited(_print(Map<String, Object?>.from(call.arguments as Map)));
      case 'cancel':
        _jobs[call.arguments as String]?.cancel();
      case 'refresh':
        unawaited(discovery.scan());
    }
    return null;
  }

  void _state(String jobId, String state, [String? message]) =>
      _channel.invokeMethod('jobState', {'jobId': jobId, 'state': state, 'message': message});

  Future<void> _print(Map<String, Object?> a) async {
    final jobId = a['jobId'] as String;
    final printer = discovery.printers.where((p) => p.id == a['printerId']).firstOrNull;
    if (printer == null || printer.capabilities == null) {
      _state(jobId, 'failed', l10n.capsUnknownYet);
      return;
    }
    PrintSource? source;
    try {
      source = await PrintSource.open(a['path'] as String);
      final ranges = [
        for (final r in (a['ranges'] as List? ?? const []))
          ((r as List)[0] as int, r[1] as int),
      ];
      final cancel = _jobs[jobId] = PrintCancel();
      // Система вже зробила PDF потрібного розміру й орієнтації — друкуємо 1:1.
      const layout = LayoutOptions(scale: LayoutScale.actual);
      final options = PrintOptions(
        color: a['color'] == true,
        duplex: a['duplex'] == true,
        copies: (a['copies'] as int?) ?? 1,
      );
      var last = '';
      await for (final p in printDocument(printer, source, options,
          pages: selectPages(ranges, source.pageCount), layout: layout, cancel: cancel)) {
        last = p.message;
        switch (p.stage) {
          case PrintStage.done:
            _state(jobId, 'done', p.message);
          case PrintStage.failed:
            _state(jobId, 'failed', p.message);
          case PrintStage.cancelled:
            _state(jobId, 'cancelled', p.message);
          default:
            _state(jobId, 'progress', p.message);
        }
      }
      if (last.isEmpty) _state(jobId, 'failed', l10n.unknownIppError);
    } catch (e) {
      _state(jobId, 'failed', '$e');
    } finally {
      _jobs.remove(jobId);
      await source?.dispose();
    }
  }
}
