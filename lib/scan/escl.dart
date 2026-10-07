// eSCL (Apple AirScan / Mopria): сканування по HTTP без драйверів. Brother DCP-J572DW і подібні.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../l10n/l10n.dart';

enum ScanColor {
  color('RGB24'),
  gray('Grayscale8'),
  blackWhite('BlackAndWhite1'); // локально з сірого — JPEG однобітним не буває

  const ScanColor(this.escl);
  final String escl;
}

/// Що вміє сканер (з /eSCL/ScannerCapabilities).
class ScannerCaps {
  final String model;
  final List<String> colorModes; // RGB24, Grayscale8, BlackAndWhite1
  final List<int> resolutions;
  final List<String> formats;
  final bool platen, adf;
  final int maxWidth, maxHeight; // у 1/300 дюйма

  const ScannerCaps({
    required this.model,
    required this.colorModes,
    required this.resolutions,
    required this.formats,
    required this.platen,
    required this.adf,
    required this.maxWidth,
    required this.maxHeight,
  });

  bool get supportsJpeg => formats.contains('image/jpeg');

  /// Розбір XML. Простими регулярками — схема стабільна, а тягнути XML-бібліотеку заради цього шкода.
  factory ScannerCaps.parse(String xml) {
    List<String> all(String tag) =>
        RegExp('<(?:scan|pwg):$tag>([^<]*)<').allMatches(xml).map((m) => m.group(1)!.trim()).toSet().toList();
    int first(String tag, int fallback) => int.tryParse(all(tag).firstOrNull ?? '') ?? fallback;
    final res = {for (final r in all('XResolution')) int.tryParse(r)}.whereType<int>().toList()..sort();
    return ScannerCaps(
      model: all('MakeAndModel').firstOrNull ?? l10n.scannerDefaultName,
      colorModes: all('ColorMode'),
      resolutions: res,
      formats: {...all('DocumentFormat'), ...all('DocumentFormatExt')}.toList(),
      platen: xml.contains('<scan:Platen>'),
      adf: xml.contains('<scan:Adf>'),
      maxWidth: first('MaxWidth', 2550),
      maxHeight: first('MaxHeight', 3507),
    );
  }
}

/// XML завдання сканування. Увага: Brother мовчки ігнорує налаштування, якщо в XML є відступи
/// чи переноси рядків, — тому все одним рядком.
String scanSettingsXml({
  required String colorMode,
  required int dpi,
  required int widthUnits, // 1/300 дюйма
  required int heightUnits,
  String format = 'image/jpeg',
  String source = 'Platen',
}) =>
    '<scan:ScanSettings xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm" '
    'xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03">'
    '<pwg:Version>2.0</pwg:Version>'
    '<pwg:ScanRegions><pwg:ScanRegion>'
    '<pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits>'
    '<pwg:XOffset>0</pwg:XOffset><pwg:YOffset>0</pwg:YOffset>'
    '<pwg:Width>$widthUnits</pwg:Width><pwg:Height>$heightUnits</pwg:Height>'
    '</pwg:ScanRegion></pwg:ScanRegions>'
    '<pwg:InputSource>$source</pwg:InputSource>'
    '<scan:ColorMode>$colorMode</scan:ColorMode>'
    '<pwg:DocumentFormat>$format</pwg:DocumentFormat>'
    '<scan:DocumentFormatExt>$format</scan:DocumentFormatExt>'
    '<scan:XResolution>$dpi</scan:XResolution><scan:YResolution>$dpi</scan:YResolution>'
    '</scan:ScanSettings>';

class ScanException implements Exception {
  final String message;
  ScanException(this.message);
  @override
  String toString() => message;
}

class EsclClient {
  EsclClient({required this.host, this.port = 80, this.root = 'eSCL'});

  final String host;
  final int port;
  final String root;

  /// [root] — з mDNS-поля `rs` (зазвичай «eSCL»; буває порожнім).
  Uri _uri(String path) {
    final r = root.replaceAll(RegExp(r'^/+|/+$'), '');
    return Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path.startsWith('/') ? path : (r.isEmpty ? '/$path' : '/$r/$path'));
  }

  Future<(int, Uint8List, HttpHeaders)> _send(String method, Uri uri,
      {String? body, Duration timeout = const Duration(seconds: 10)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        // Явна довжина: без неї Dart шле тіло частинами (chunked), а Brother цього не розуміє й мовчить.
        final bytes = utf8.encode(body);
        req.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final resp = await req.close().timeout(timeout);
      final data = await resp.fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c)).timeout(timeout);
      return (resp.statusCode, data.takeBytes(), resp.headers);
    } on TimeoutException {
      throw ScanException(l10n.scannerNotResponding);
    } on SocketException catch (e) {
      throw ScanException(l10n.noConnectionScanner(e.osError?.message ?? e.message));
    } finally {
      client.close(force: true);
    }
  }

  /// Можливості сканера; null — eSCL тут немає (напр. Xerox 3225).
  Future<ScannerCaps?> capabilities({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final (status, data, _) = await _send('GET', _uri('ScannerCapabilities'), timeout: timeout);
      if (status != 200) return null;
      final xml = String.fromCharCodes(data);
      return xml.contains('ScannerCapabilities') ? ScannerCaps.parse(xml) : null;
    } on ScanException {
      return null;
    }
  }

  /// Виконує завдання й повертає всі сторінки (JPEG): зі скла — одну, з подавача — скільки там
  /// аркушів. Сторінки читаються, поки сканер не скаже 404 («більше нема»); при помилці завдання
  /// видаляється — інакше сканер лишається «зайнятим». [onPage] — після кожної сторінки.
  Future<List<Uint8List>> scan(String settingsXml, {void Function(int pages)? onPage}) async {
    final (status, _, headers) = await _send('POST', _uri('ScanJobs'), body: settingsXml);
    if (status == 503) throw ScanException(l10n.scannerBusy);
    if (status == 409) throw ScanException(l10n.scannerUnsupportedSettings);
    if (status != 201) throw ScanException(l10n.scannerRejected(status));
    final location = headers.value(HttpHeaders.locationHeader);
    if (location == null) throw ScanException(l10n.scannerNoJobAddress);
    // Лише шлях: хост у Location буває ім'ям, яке телефон не розв'яже (напр. ім'я домашнього сервера).
    final job = Uri.parse(location).path;
    final pages = <Uint8List>[];
    try {
      var waits = 0;
      while (true) {
        final (st, data, _) = await _send('GET', _uri('$job/NextDocument'), timeout: const Duration(seconds: 90));
        if (st == 200) {
          pages.add(data);
          onPage?.call(pages.length);
          waits = 0;
          continue;
        }
        if (st == 404) {
          if (pages.isEmpty) throw ScanException(l10n.scannerNothing);
          return pages;
        }
        if (st != 503 || ++waits > 60) throw ScanException(l10n.scannerNoPage(st));
        await Future<void>.delayed(const Duration(seconds: 1)); // ще сканує
      }
    } catch (_) {
      await _send('DELETE', _uri(job)).catchError((_) => (0, Uint8List(0), headers));
      rethrow;
    }
  }
}

/// Знайдений сканер: як до нього звертатися й що він уміє. Буває на самому принтері (Brother)
/// або на окремому шлюзі (напр. AirSane на домашньому сервері для Xerox).
class ScannerRef {
  ScannerRef({required this.id, required this.name, required this.client, required this.caps, DateTime? lastSeen})
      : lastSeen = lastSeen ?? DateTime.now();

  final String id;
  final String name;
  final EsclClient client;
  final ScannerCaps caps;
  DateTime lastSeen;

  String get host => client.host;
}

/// Назва для порівняння принтера зі сканером: без регістру, без префікса шлюзу «WSD».
String scannerMatchName(String s) =>
    s.toLowerCase().replaceFirst(RegExp(r'^\s*wsd\s+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Чи це сканер того самого пристрою: та сама адреса або назва одна в одній.
bool scannerMatchesPrinter(
    {required String scannerName,
    required String scannerHost,
    required String printerName,
    required String printerHost,
    String? printerModel}) {
  if (scannerHost == printerHost) return true;
  final s = scannerMatchName(scannerName);
  for (final p in [printerName, if (printerModel != null) printerModel]) {
    final n = scannerMatchName(p);
    if (s.length >= 6 && n.length >= 6 && (s.contains(n) || n.contains(s))) return true; // коротке «HP» — не вгадуємо
  }
  return false;
}
