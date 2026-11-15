// Принтери KamiDrop у Windows: наш IPP-сервер (ipp_server.dart) + справжній друк тим самим
// конвеєром, що й служба друку Android, + додавання/прибирання принтерів у системі.
import 'dart:convert';
import 'dart:io';

import '../discovery/discovery.dart';
import '../printing/compose.dart';
import '../printing/print_service.dart';
import '../printing/sources.dart';
import 'ipp_server.dart';

class PrintProxyHost {
  PrintProxyHost(this.discovery);

  final PrinterDiscovery discovery;
  late final server = IppProxyServer(printers: _printers, onJob: _print);

  static const _suffix = ' (KamiDrop)';

  /// Назва принтера в Windows.
  static String systemName(DiscoveredPrinter p) => '${_model(p)}$_suffix';

  static String _model(DiscoveredPrinter p) {
    final model = p.capabilities?.model ?? '';
    return model.isEmpty ? p.name : model;
  }

  Iterable<DiscoveredPrinter> get _ready =>
      discovery.printers.where((p) => p.capabilities != null && p.capabilities!.supportsUrf);

  List<ProxyPrinter> _printers() => [
        for (final p in _ready)
          ProxyPrinter(
            slug: proxySlug(p.id),
            name: _model(p),
            color: p.capabilities!.supportsColor,
            duplex: p.capabilities!.supportsDuplex,
            dpi: p.capabilities!.defaultDpi,
            margin: ([
                      p.capabilities!.margins.top,
                      p.capabilities!.margins.bottom,
                      p.capabilities!.margins.left,
                      p.capabilities!.margins.right,
                    ].reduce((a, b) => a > b ? a : b) *
                    100)
                .round(),
          ),
      ];

  /// Сервер не стартував (порт зайнятий другим KamiDrop тощо) — тихо лишаємось без нього.
  Future<bool> start() async {
    try {
      await server.start();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<bool> _print(ProxyJob job) async {
    final printer = _ready.where((p) => proxySlug(p.id) == job.slug).firstOrNull;
    if (printer == null) return false;
    final source = await PrintSource.open(job.path);
    try {
      var ok = false;
      // Система вже зробила PDF потрібного розміру й орієнтації — друкуємо 1:1.
      await for (final p in printDocument(
        printer,
        source,
        PrintOptions(color: job.color, duplex: job.duplex, copies: job.copies),
        layout: const LayoutOptions(scale: LayoutScale.actual),
      )) {
        ok = p.stage == PrintStage.done;
      }
      return ok;
    } finally {
      await source.dispose();
    }
  }

  // ------------------------------------------------------------ принтери в Windows

  static Future<List<String>> _systemPrinters() async {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-Command', '[Console]::OutputEncoding=[Text.Encoding]::UTF8; (Get-Printer).Name'],
      stdoutEncoding: utf8,
    );
    return LineSplitter.split('${r.stdout}').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  /// Наші принтери, які вже є в системі.
  static Future<List<String>> installed() async =>
      (await _systemPrinters()).where((n) => n.endsWith(_suffix)).toList();

  /// Чужі принтери системи, що схожі на наші (той самий апарат через драйвер виробника).
  // ponytail: порівнюємо за назвою моделі; точніше було б за адресою порту, але WSD-порти її не показують
  Future<List<String>> duplicates() async {
    final models = [for (final p in _ready) _model(p).toLowerCase()];
    return (await _systemPrinters())
        .where((n) => !n.endsWith(_suffix) && models.any((m) => n.toLowerCase().contains(m)))
        .toList();
  }

  /// Скрипт від імені адміністратора (Windows покаже запит UAC). false — відмовили або помилка.
  static Future<bool> _elevated(String script) async {
    final bytes = <int>[];
    for (final u in script.codeUnits) {
      bytes
        ..add(u & 0xff)
        ..add(u >> 8); // -EncodedCommand чекає UTF-16LE
    }
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "\$p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru "
          "-ArgumentList '-NoProfile','-EncodedCommand','${base64.encode(bytes)}'; exit \$p.ExitCode",
    ]);
    return r.exitCode == 0;
  }

  static String _q(String s) => "'${s.replaceAll("'", "''")}'";

  /// Додає в Windows усі знайдені принтери, яких там ще немає. Повертає назви доданих;
  /// null — не вдалося (немає принтерів, сервер не стартував, відмова в UAC).
  Future<List<String>?> addToSystem() async {
    if (!await start()) return null;
    final have = await installed();
    final missing = _ready.where((p) => !have.contains(systemName(p))).toList();
    if (missing.isEmpty) return have.isEmpty ? null : const [];
    final script = [
      r"$ErrorActionPreference = 'Stop'",
      for (final p in missing)
        'Add-Printer -Name ${_q(systemName(p))} '
            '-IppURL ${_q('http://localhost:${server.port}/ipp/print/${proxySlug(p.id)}')}',
    ].join('\n');
    return await _elevated(script) ? [for (final p in missing) systemName(p)] : null;
  }

  static Future<bool> removeFromSystem(List<String> names) =>
      _elevated(["\$ErrorActionPreference = 'Stop'", for (final n in names) 'Remove-Printer -Name ${_q(n)}'].join('\n'));
}
