// KamiDrop як IPP-принтер на localhost: система (Windows, «Microsoft IPP Class Driver») додає
// його як звичайний принтер і надсилає PDF із налаштуваннями — друк із будь-якої програми.
// Відповідник служби друку Android. Чистий Dart, без Flutter.
//
// Адреса принтера: http://localhost:<порт>/ipp/print/<slug>. Windows робить
// Get-Printer-Attributes → Validate-Job → Create-Job → Send-Document → Get-Job-Attributes.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../ipp/ipp.dart';

/// Принтер, яким ми прикидаємось перед системою.
class ProxyPrinter {
  final String slug; // частина адреси; не змінюється між запусками
  final String name;
  final bool color;
  final bool duplex;
  final int dpi;
  final int margin; // недрукове поле справжнього принтера, сота мм
  const ProxyPrinter({
    required this.slug,
    required this.name,
    this.color = false,
    this.duplex = false,
    this.dpi = 300,
    this.margin = 0,
  });
}

/// Завдання від системи: PDF у тимчасовому файлі + те, що вибрали в діалозі друку.
class ProxyJob {
  final String slug;
  final String path;
  final String name;
  final int copies;
  final bool color;
  final bool duplex;
  const ProxyJob({
    required this.slug,
    required this.path,
    required this.name,
    required this.copies,
    required this.color,
    required this.duplex,
  });
}

/// Частина адреси з id принтера: лише латиниця, цифри й дефіс.
String proxySlug(String printerId) => printerId.replaceAll(RegExp('[^A-Za-z0-9]+'), '-');

/// Сталий UUID принтера-проксі: Windows без printer-uuid пристрій «не знаходить». Навмисно не той,
/// що у справжнього принтера, — інакше система сплутала б нас із ним.
String proxyUuid(String slug) {
  var h1 = 0x6b616d6964726f70, h2 = 0x70726f7879697070; // FNV-подібне змішування, двічі по 64 біти
  for (final c in slug.codeUnits) {
    h1 = (h1 ^ c) * 0x100000001b3;
    h2 = ((h2 ^ c) * 0x100000001b3) ^ (h2 >>> 29);
  }
  final d = ByteData(16)
    ..setInt64(0, h1)
    ..setInt64(8, h2);
  final hex = [for (var i = 0; i < 16; i++) d.getUint8(i).toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class IppProxyServer {
  IppProxyServer({required this.printers, required this.onJob, this.port = defaultPort});

  static const defaultPort = 8631;
  static const _pending = 3, _processing = 5, _aborted = 8, _completed = 9;

  /// Принтери, які є зараз (питаємо щоразу — список змінюється).
  final List<ProxyPrinter> Function() printers;

  /// Друкує завдання; null — вийшло, інакше причина невдачі. Файл після цього видаляємо самі.
  final Future<String?> Function(ProxyJob job) onJob;
  final int port;

  HttpServer? _server;
  var _nextJob = 1;
  final _jobs = <int, _Job>{};

  bool get running => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    // Лише loopback: ззовні комп'ютера принтер не видно.
    final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen(_onRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _onRequest(HttpRequest r) async {
    try {
      final segments = r.uri.pathSegments;
      if (r.method != 'POST' || segments.length < 3 || segments[0] != 'ipp' || segments[1] != 'print') {
        r.response.statusCode = HttpStatus.notFound;
        return;
      }
      final body = (await r.fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c))).takeBytes();
      final out = await handle(segments[2], body);
      r.response.headers.contentType = ContentType('application', 'ipp');
      r.response.contentLength = out.length;
      r.response.add(out);
    } catch (_) {
      r.response.statusCode = HttpStatus.badRequest;
    } finally {
      await r.response.close().catchError((_) {});
    }
  }

  /// Відповідь на один IPP-запит (окремо від HTTP — так простіше тестувати).
  Future<Uint8List> handle(String slug, Uint8List req) async {
    final parsed = parseIppResponse(req); // у запиті на місці статусу — код операції
    final printer = printers().where((p) => p.slug == slug).firstOrNull;
    final uri = 'ipp://localhost:$port/ipp/print/$slug';
    // Відповідь має ту саму версію й request-id, що й запит.
    final b = IppRequestBuilder(0, requestId: ByteData.sublistView(req).getInt32(4), version: IppVersion(req[0], req[1]))
      ..group(IppTag.operationAttributes)
      ..string(IppTag.charset, 'attributes-charset', 'utf-8')
      ..string(IppTag.naturalLanguage, 'attributes-natural-language', 'en');

    void jobGroup(int id) {
      final state = _jobs[id]?.state ?? _completed;
      b
        ..group(IppTag.jobAttributes)
        ..integer('job-id', id)
        ..string(IppTag.uri, 'job-uri', '$uri/$id')
        ..integer('job-state', state, tag: IppTag.enumValue)
        ..string(IppTag.keyword, 'job-state-reasons',
            state == _completed ? 'job-completed-successfully' : (state == _aborted ? 'aborted-by-system' : 'none'));
      final message = _jobs[id]?.message;
      if (message != null) b.string(IppTag.text, 'job-state-message', message);
    }

    switch (parsed.status) {
      case IppOp.getPrinterAttributes:
        _printerAttributes(b, printer, uri, slug);
      case IppOp.validateJob || IppOp.getJobs:
        break;
      case IppOp.createJob:
        final id = _nextJob++;
        _jobs[id] = _Job(parsed, _pending);
        jobGroup(id);
      case IppOp.printJob || IppOp.sendDocument:
        final id = parsed.status == IppOp.printJob ? _nextJob++ : (parsed.first<int>('job-id') ?? 0);
        // Налаштування друку Windows надсилає в Create-Job, документ — у Send-Document.
        final job = _jobs[id] ??= _Job(parsed, _pending);
        // Навіть якщо принтера зараз не видно: onJob сам вирішує, скільки на нього чекати.
        job.state = _processing;
        unawaited(_run(id, job, slug, Uint8List.sublistView(req, parsed.bodyOffset)));
        jobGroup(id);
      case IppOp.getJobAttributes:
        jobGroup(parsed.first<int>('job-id') ?? 0);
      case IppOp.cancelJob:
        break; // ponytail: скасування з черги Windows не зупиняє друк; додати, коли знадобиться
      default:
        return IppRequestBuilder(0x0501, // server-error-operation-not-supported
                requestId: ByteData.sublistView(req).getInt32(4), version: IppVersion(req[0], req[1]))
            .build();
    }
    return b.build();
  }

  Future<void> _run(int id, _Job job, String slug, Uint8List document) async {
    final a = job.attributes;
    final file = File('${Directory.systemTemp.path}/kamidrop-job-$pid-$id.pdf');
    try {
      await file.writeAsBytes(document);
      job.message = await onJob(ProxyJob(
        slug: slug,
        path: file.path,
        name: a.first<String>('job-name') ?? 'KamiDrop',
        copies: a.first<int>('copies') ?? 1,
        color: a.first<String>('print-color-mode') != 'monochrome',
        duplex: (a.first<String>('sides') ?? 'one-sided') != 'one-sided',
      ));
      job.state = job.message == null ? _completed : _aborted;
    } catch (e) {
      job
        ..message = '$e'
        ..state = _aborted;
    } finally {
      await file.delete().catchError((_) => file);
      // Windows ще кілька разів спитає стан; старі завдання тримати нема чого.
      Timer(const Duration(minutes: 10), () => _jobs.remove(id));
    }
  }

  void _printerAttributes(IppRequestBuilder b, ProxyPrinter? p, String uri, String slug) {
    Uint8List u32(int v) => Uint8List(4)..buffer.asByteData().setInt32(0, v);
    void enums(String name, List<int> values) {
      for (var i = 0; i < values.length; i++) {
        b.integer(i == 0 ? name : '', values[i], tag: IppTag.enumValue);
      }
    }

    const a4 = {'x-dimension': 21000, 'y-dimension': 29700}; // сота мм
    final dpi = p?.dpi ?? 300;
    final res = [...u32(dpi), ...u32(dpi), 3];
    final name = p?.name ?? 'KamiDrop';
    b
      ..group(IppTag.printerAttributes)
      ..string(IppTag.uri, 'printer-uri-supported', uri)
      ..string(IppTag.keyword, 'uri-security-supported', 'none')
      ..string(IppTag.keyword, 'uri-authentication-supported', 'none')
      ..string(IppTag.name, 'printer-name', name)
      ..string(IppTag.text, 'printer-info', name)
      ..string(IppTag.text, 'printer-make-and-model', '$name (KamiDrop)')
      ..string(IppTag.uri, 'printer-uuid', 'urn:uuid:${proxyUuid(slug)}')
      ..string(IppTag.text, 'printer-device-id', 'MFG:KamiDrop;MDL:$name;CMD:PDF;')
      // 3 — готовий, 5 — зупинений (справжнього принтера зараз не видно).
      ..integer('printer-state', p == null ? 5 : 3, tag: IppTag.enumValue)
      ..string(IppTag.keyword, 'printer-state-reasons', p == null ? 'offline-report' : 'none')
      ..attr(IppTag.boolean, 'printer-is-accepting-jobs', [p == null ? 0 : 1])
      ..integer('queued-job-count', 0)
      ..integer('printer-up-time', DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000 + 1)
      ..strings(IppTag.keyword, 'ipp-versions-supported', ['1.1', '2.0']);
    enums('operations-supported', [
      IppOp.printJob, IppOp.validateJob, IppOp.createJob, IppOp.sendDocument, //
      IppOp.cancelJob, IppOp.getJobAttributes, IppOp.getJobs, IppOp.getPrinterAttributes,
    ]);
    b
      ..string(IppTag.charset, 'charset-configured', 'utf-8')
      ..string(IppTag.charset, 'charset-supported', 'utf-8')
      ..string(IppTag.naturalLanguage, 'natural-language-configured', 'en')
      ..string(IppTag.naturalLanguage, 'generated-natural-language-supported', 'en')
      // Лише PDF: його ми вже вміємо друкувати, а Windows сама його й обирає.
      ..string(IppTag.mimeType, 'document-format-default', 'application/pdf')
      ..string(IppTag.mimeType, 'document-format-supported', 'application/pdf')
      ..strings(IppTag.keyword, 'pdf-versions-supported', ['adobe-1.4', 'adobe-1.5', 'adobe-1.6', 'adobe-1.7'])
      ..string(IppTag.keyword, 'compression-supported', 'none')
      ..string(IppTag.keyword, 'pdl-override-supported', 'attempted')
      ..strings(IppTag.keyword, 'job-creation-attributes-supported',
          ['copies', 'sides', 'media', 'media-col', 'print-color-mode', 'print-quality', 'orientation-requested'])
      ..attr(IppTag.boolean, 'color-supported', [p?.color == true ? 1 : 0])
      ..strings(IppTag.keyword, 'print-color-mode-supported',
          p?.color == true ? ['auto', 'color', 'monochrome'] : ['auto', 'monochrome'])
      ..string(IppTag.keyword, 'print-color-mode-default', 'auto')
      ..strings(IppTag.keyword, 'sides-supported',
          p?.duplex == true ? ['one-sided', 'two-sided-long-edge', 'two-sided-short-edge'] : ['one-sided'])
      ..string(IppTag.keyword, 'sides-default', 'one-sided')
      ..attr(IppTag.rangeOfInteger, 'copies-supported', [...u32(1), ...u32(99)])
      ..integer('copies-default', 1);
    enums('print-quality-supported', [4]);
    b.integer('print-quality-default', 4, tag: IppTag.enumValue);
    enums('orientation-requested-supported', [3, 4]);
    b
      ..integer('orientation-requested-default', 3, tag: IppTag.enumValue)
      ..attr(IppTag.resolution, 'printer-resolution-supported', res)
      ..attr(IppTag.resolution, 'printer-resolution-default', res)
      // ponytail: лише A4 (як і весь KamiDrop); інші розміри — разом із підтримкою в конвеєрі друку
      ..string(IppTag.keyword, 'media-supported', 'iso_a4_210x297mm')
      ..string(IppTag.keyword, 'media-default', 'iso_a4_210x297mm')
      ..string(IppTag.keyword, 'media-ready', 'iso_a4_210x297mm')
      ..collection('media-size-supported', a4)
      ..collection('media-col-default', {'media-size': a4})
      ..collection('media-col-ready', {'media-size': a4})
      ..collection('media-col-database', {'media-size': a4})
      ..strings(IppTag.keyword, 'media-col-supported',
          ['media-size', 'media-top-margin', 'media-bottom-margin', 'media-left-margin', 'media-right-margin'])
      ..integer('media-top-margin-supported', p?.margin ?? 0)
      ..integer('media-bottom-margin-supported', p?.margin ?? 0)
      ..integer('media-left-margin-supported', p?.margin ?? 0)
      ..integer('media-right-margin-supported', p?.margin ?? 0);
  }
}

class _Job {
  _Job(this.attributes, this.state);
  final IppResponse attributes; // запит Create-Job / Print-Job з налаштуваннями
  int state;
  String? message; // чому не надрукувалось
}
