import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'ipp.dart';

class IppException implements Exception {
  final String message;
  IppException(this.message);
  @override
  String toString() => message;
}

/// HTTP-транспорт для IPP (IPP — це просто POST з Content-Type: application/ipp).
class IppClient {
  final String host;
  final int port;
  final String path;
  final bool tls;
  IppVersion version;

  IppClient({
    required this.host,
    this.port = 631,
    this.path = 'ipp/print',
    this.tls = false,
    this.version = IppVersion.v20,
  });

  String get _normalizedPath => path.startsWith('/') ? path.substring(1) : path;

  Uri get httpUri => Uri(scheme: tls ? 'https' : 'http', host: host, port: port, path: '/$_normalizedPath');

  String get printerUri {
    final h = host.contains(':') ? '[$host]' : host;
    return '${tls ? 'ipps' : 'ipp'}://$h:$port/$_normalizedPath';
  }

  Future<IppResponse> send(Uint8List body, {Duration timeout = const Duration(seconds: 8)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (tls) client.badCertificateCallback = (cert, host, port) => true; // принтери мають самопідписані сертифікати
    try {
      final req = await client.postUrl(httpUri).timeout(timeout);
      req.headers.contentType = ContentType('application', 'ipp');
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(timeout);
      final bytes = await resp
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) => b..add(chunk))
          .timeout(timeout);
      if (resp.statusCode != HttpStatus.ok) {
        throw IppException('HTTP ${resp.statusCode}');
      }
      return parseIppResponse(bytes.takeBytes());
    } on TimeoutException {
      throw IppException('Принтер не відповідає. Спробуй його перезавантажити.');
    } on SocketException catch (e) {
      throw IppException('Немає з\'єднання з принтером: ${e.osError?.message ?? e.message}');
    } on HttpException catch (e) {
      throw IppException('Принтер розірвав з\'єднання: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Get-Printer-Attributes. Якщо IPP 2.0 не спрацював — пробує 1.1 і запам'ятовує версію.
  Future<IppResponse> getPrinterAttributes() async {
    IppException? lastError;
    for (final v in {version, IppVersion.v20, IppVersion.v11}) {
      final body = (IppRequestBuilder.standard(IppOp.getPrinterAttributes, printerUri, version: v)
            ..string(IppTag.keyword, 'requested-attributes', 'all'))
          .build();
      try {
        final r = await send(body);
        if (r.isSuccess && r['document-format-supported'].isNotEmpty) {
          version = v;
          return r;
        }
        lastError = IppException('Принтер відповів помилкою ${r.statusHex}');
      } on IppException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? IppException('Невідома помилка IPP');
  }

  Future<IppResponse> printJob({
    required Uint8List document,
    required String documentFormat,
    required String jobName,
    required String userName,
    Map<String, String> keywords = const {},
    Map<String, int> integers = const {},
    Map<String, Map<String, Object>> collections = const {},
  }) {
    final b = IppRequestBuilder.standard(IppOp.printJob, printerUri, requestId: 2, version: version)
      ..string(IppTag.name, 'requesting-user-name', userName)
      ..string(IppTag.name, 'job-name', jobName)
      ..string(IppTag.mimeType, 'document-format', documentFormat)
      ..group(IppTag.jobAttributes);
    keywords.forEach((k, v) => b.string(IppTag.keyword, k, v));
    integers.forEach((k, v) => b.integer(k, v));
    collections.forEach(b.collection);
    return send(b.build(document: document), timeout: const Duration(minutes: 3));
  }

  Future<IppResponse> cancelJob(int jobId, {required String userName}) {
    final b = IppRequestBuilder.standard(IppOp.cancelJob, printerUri, requestId: 4, version: version)
      ..integer('job-id', jobId)
      ..string(IppTag.name, 'requesting-user-name', userName);
    return send(b.build());
  }

  Future<IppResponse> getJobAttributes(int jobId) {
    final b = IppRequestBuilder.standard(IppOp.getJobAttributes, printerUri, requestId: 3, version: version)
      ..integer('job-id', jobId)
      ..strings(IppTag.keyword, 'requested-attributes', ['job-state', 'job-state-reasons']);
    return send(b.build());
  }
}
