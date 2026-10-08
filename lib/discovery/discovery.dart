import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:path_provider/path_provider.dart';

import '../ipp/ipp_client.dart';
import '../platform/platform_bridge.dart';
import '../printing/capabilities.dart';
import '../scan/escl.dart';
import '../l10n/l10n.dart';

/// Принтер, знайдений у локальній мережі через mDNS (DNS-SD `_ipp._tcp` / `_ipps._tcp`).
class DiscoveredPrinter {
  final String id; // UUID з TXT або ім'я сервісу
  String name;
  String host;
  int port;
  String path;
  bool tls;
  Map<String, String> txt;
  DateTime lastSeen;

  PrinterCapabilities? capabilities;
  ScannerRef? scanner; // eSCL на самому принтері (напр. Brother); null — нема або ще не перевіряли
  bool scannerProbed = false;
  String? error;
  bool loading = false;

  DiscoveredPrinter({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.path,
    required this.tls,
    required this.txt,
    required this.lastSeen,
  });

  IppClient client() => IppClient(host: host, port: port, path: path, tls: tls);
}

/// Постійний фоновий пошук принтерів. Wi-Fi-принтери відповідають на mDNS нерегулярно,
/// тож скануємо періодично й пам'ятаємо знайдені, поки вони не зникнуть надовго.
class PrinterDiscovery extends ChangeNotifier {
  PrinterDiscovery({
    this.interval = const Duration(seconds: 20),
    this.forgetAfter = const Duration(minutes: 3),
  });

  final Duration interval;
  final Duration forgetAfter;

  final Map<String, DiscoveredPrinter> _printers = {};
  final Map<String, ScannerRef> _scanners = {}; // з mDNS _uscan._tcp
  final Set<String> _scannerProbing = {};
  Timer? _timer;
  bool _scanning = false;
  bool _disposed = false;
  DateTime? _lastNativeStart;
  String? lastError;

  bool get scanning => _scanning;

  List<DiscoveredPrinter> get printers {
    final list = _printers.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Сканер цього принтера: на ньому самому або знайдений у мережі (напр. шлюз для Xerox).
  ScannerRef? scannerFor(DiscoveredPrinter p) =>
      p.scanner ??
      _scanners.values.where((s) => scannerMatchesPrinter(
          scannerName: s.name,
          scannerHost: s.host,
          printerName: p.name,
          printerHost: p.host,
          printerModel: p.capabilities?.model)).firstOrNull;

  /// Сканери, яким не знайшлося пари серед принтерів, — показуємо окремо.
  List<ScannerRef> get standaloneScanners {
    final printers = _printers.values.toList();
    return _scanners.values
        .where((s) =>
            !printers.any((p) => p.scanner != null && p.scanner!.host == s.host) &&
            !printers.any((p) => scannerMatchesPrinter(
                scannerName: s.name,
                scannerHost: s.host,
                printerName: p.name,
                printerHost: p.host,
                printerModel: p.capabilities?.model)))
        .toList();
  }

  /// Сканер з mDNS: перевіряємо можливості й запам'ятовуємо (або оновлюємо «живий»).
  Future<void> _onScannerFound(String name, String host, int port, Map<String, String> txt) async {
    final id = txt['uuid'] ?? '$host:$port';
    final known = _scanners[id];
    if (known != null && known.host == host && known.client.port == port) {
      known.lastSeen = DateTime.now();
      return;
    }
    if (!_scannerProbing.add(id)) return;
    try {
      final client = EsclClient(host: host, port: port, root: txt['rs'] ?? 'eSCL');
      final caps = await client.capabilities();
      if (caps == null || !caps.supportsJpeg || _disposed) return;
      _scanners[id] = ScannerRef(id: id, name: txt['ty'] ?? name, client: client, caps: caps);
      _notify();
    } finally {
      _scannerProbing.remove(id);
    }
  }

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => scan());
    _loadKnown(); // відомі принтери з'являються одразу, не чекаючи mDNS
    // Кілька швидких сканів на старті: Wi-Fi-принтери часто пропускають перший запит.
    scan();
    for (final s in const [4, 10]) {
      Future<void>.delayed(Duration(seconds: s), scan);
    }
  }

  // ---------------------------------------------------------------- пам'ять принтерів

  /// Принтери, які колись знаходили. Між запусками зберігаються у файлі,
  /// тож відомий принтер видно одразу, навіть якщо mDNS цього разу мовчить.
  final Map<String, Map<String, Object?>> _known = {};

  Future<File> _knownFile() async => File('${(await getApplicationSupportDirectory()).path}/printers.json');

  Future<void> _loadKnown() async {
    try {
      final f = await _knownFile();
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      for (final raw in list.cast<Map<String, dynamic>>()) {
        final id = raw['id'] as String;
        _known[id] = raw;
        if (_printers.containsKey(id)) continue;
        final manual = raw['manual'] == true;
        final p = DiscoveredPrinter(
          id: id,
          name: raw['name'] as String,
          host: raw['host'] as String,
          port: raw['port'] as int,
          path: raw['path'] as String,
          tls: raw['tls'] as bool,
          txt: (raw['txt'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, '$v')),
          lastSeen: manual ? DateTime.now().add(const Duration(days: 3650)) : DateTime.now(),
        );
        _printers[id] = p;
        refreshCapabilities(p);
      }
      _notify();
    } catch (e) {
      debugPrint('Не вдалося прочитати збережені принтери: $e');
    }
  }

  void _remember(DiscoveredPrinter p, {bool manual = false}) {
    final entry = <String, Object?>{
      'id': p.id,
      'name': p.name,
      'host': p.host,
      'port': p.port,
      'path': p.path,
      'tls': p.tls,
      'txt': p.txt,
      'manual': manual || (_known[p.id]?['manual'] == true),
    };
    final old = _known[p.id];
    if (old != null && jsonEncode(old) == jsonEncode(entry)) return;
    _known[p.id] = entry;
    _saveKnown();
  }

  Future<void> _saveKnown() async {
    try {
      final f = await _knownFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_known.values.toList()));
    } catch (e) {
      debugPrint('Не вдалося зберегти принтери: $e');
    }
  }

  Future<void> scan() async {
    if (_scanning || _disposed) return;
    _scanning = true;
    _notify();

    if (PlatformBridge.hasNativeDiscovery) {
      // Android: шукає система (NsdManager), результати приходять у _onNativeFound.
      // Перезапуск змушує її знову опитати мережу; відомі принтери паралельно перевіряємо по IPP.
      // Не перезапускаємо надто часто, щоб не обривати розв'язування повільних принтерів.
      final now = DateTime.now();
      if (_lastNativeStart == null || now.difference(_lastNativeStart!) > const Duration(seconds: 15)) {
        _lastNativeStart = now;
        await PlatformBridge.startPrinterDiscovery(_onNativeFound);
      }
      for (final p in _printers.values) {
        if (!p.loading) refreshCapabilities(p);
      }
      await Future<void>.delayed(const Duration(seconds: 4));
      _scanning = false;
      _prune();
      _notify();
      return;
    }

    // Android і Windows не підтримують reusePort для UDP-сокетів — там одразу прив'язуємося без нього.
    var client = Platform.isAndroid || Platform.isWindows ? MDnsClient(rawDatagramSocketFactory: _bindWithoutReusePort) : MDnsClient();
    try {
      try {
        await client.start();
      } on SocketException {
        // Деякі системи (часто Android) не дозволяють reusePort на порту 5353 — пробуємо без нього.
        client = MDnsClient(rawDatagramSocketFactory: _bindWithoutReusePort);
        await client.start();
      }
      final found = <_Found>[];
      for (final type in const ['_ipp._tcp.local', '_ipps._tcp.local', '_uscan._tcp.local']) {
        final ptrs = <String>{};
        await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(type),
          timeout: const Duration(seconds: 4),
        )) {
          ptrs.add(ptr.domainName);
        }
        final resolved = await Future.wait(ptrs.map((n) => _resolve(client, n, tls: type.startsWith('_ipps'))));
        if (type.startsWith('_uscan')) {
          for (final f in resolved.whereType<_Found>()) {
            _onScannerFound(f.name, f.host, f.port, f.txt);
          }
          continue;
        }
        found.addAll(resolved.whereType<_Found>());
      }
      final seen = _merge(found);
      lastError = null;
      // Принтери, що цього разу не відповіли на mDNS, перевіряємо напряму по IPP:
      // якщо відповідають — вони на місці, просто mDNS-пакет загубився.
      for (final p in _printers.values) {
        if (!seen.contains(p.id) && !p.loading) refreshCapabilities(p);
      }
    } catch (e) {
      lastError = l10n.searchFailed('$e');
    } finally {
      client.stop();
      _scanning = false;
      _prune();
      _notify();
    }
  }

  void _onNativeFound(Map<String, Object?> s) {
    if (_disposed) return;
    final host = s['host'], port = s['port'], name = s['name'];
    if (host is! String || port is! int || name is! String) return;
    final txtRaw = s['txt'];
    final txt = <String, String>{
      if (txtRaw is Map)
        for (final e in txtRaw.entries) '${e.key}'.toLowerCase(): '${e.value}',
    };
    if (s['scanner'] == true) {
      _onScannerFound(name, host, port, txt);
      return;
    }
    _merge([_Found(name: name, host: host, port: port, tls: s['tls'] == true, txt: txt)]);
    _notify();
  }

  Future<_Found?> _resolve(MDnsClient client, String serviceName, {required bool tls}) async {
    final srv = await _first<SrvResourceRecord>(client, ResourceRecordQuery.service(serviceName));
    if (srv == null) return null;
    final txtRecord = await _first<TxtResourceRecord>(client, ResourceRecordQuery.text(serviceName));
    final ip = await _first<IPAddressResourceRecord>(client, ResourceRecordQuery.addressIPv4(srv.target));

    final txt = <String, String>{};
    for (final entry in (txtRecord?.text ?? '').split('\n')) {
      final eq = entry.indexOf('=');
      if (eq > 0) txt[entry.substring(0, eq).toLowerCase()] = entry.substring(eq + 1);
    }
    final instance = serviceName.split(RegExp(r'\._(ipps?|uscan)\._tcp')).first;
    return _Found(
      name: instance.replaceAll(r'\032', ' ').replaceAll(r'\ ', ' '),
      host: ip?.address.address ?? srv.target,
      port: srv.port,
      tls: tls,
      txt: txt,
    );
  }

  static Future<RawDatagramSocket> _bindWithoutReusePort(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 1,
  }) {
    return RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: false, ttl: ttl);
  }

  static Future<T?> _first<T extends ResourceRecord>(MDnsClient c, ResourceRecordQuery q) async {
    try {
      return await c.lookup<T>(q, timeout: const Duration(seconds: 2)).first;
    } catch (_) {
      return null; // запис не прийшов за відведений час
    }
  }

  Set<String> _merge(List<_Found> found) {
    final now = DateTime.now();
    final seen = <String>{};
    for (final f in found) {
      final id = f.txt['uuid'] ?? f.name;
      seen.add(id);
      final existing = _printers[id];
      if (existing == null) {
        final p = DiscoveredPrinter(
          id: id,
          name: f.name,
          host: f.host,
          port: f.port,
          path: f.txt['rp'] ?? 'ipp/print',
          tls: f.tls,
          txt: f.txt,
          lastSeen: now,
        );
        _printers[id] = p;
        _remember(p);
        refreshCapabilities(p);
        continue;
      }
      if (existing.lastSeen.isBefore(now)) existing.lastSeen = now;
      // Звичайний ipp зручніший за ipps (самопідписані сертифікати), тож не перемикаємося на TLS.
      if ((existing.tls && !f.tls) || (existing.host != f.host && existing.tls == f.tls)) {
        existing
          ..host = f.host
          ..port = f.port
          ..tls = f.tls
          ..path = f.txt['rp'] ?? existing.path
          ..txt = f.txt;
        _remember(existing);
        refreshCapabilities(existing);
      } else if (existing.capabilities == null && !existing.loading) {
        refreshCapabilities(existing);
      }
    }
    return seen;
  }

  void _prune() {
    final now = DateTime.now();
    _printers.removeWhere((_, p) => now.difference(p.lastSeen) > forgetAfter);
    _scanners.removeWhere((_, s) => now.difference(s.lastSeen) > forgetAfter);
  }

  Future<void> refreshCapabilities(DiscoveredPrinter p) async {
    p.loading = true;
    _notify();
    try {
      final r = await p.client().getPrinterAttributes();
      p.capabilities = PrinterCapabilities.fromIpp(r, txt: p.txt);
      p.error = null;
      final now = DateTime.now();
      if (p.lastSeen.isBefore(now)) p.lastSeen = now; // відповів по IPP — отже, живий
      if (!p.scannerProbed) _probeScanner(p);
    } catch (e) {
      p.error = '$e';
    } finally {
      p.loading = false;
      _notify();
    }
  }

  /// Один раз дивимось, чи є на тій самій адресі сканер eSCL (звичайний HTTP-запит на порт 80).
  Future<void> _probeScanner(DiscoveredPrinter p) async {
    p.scannerProbed = true;
    final client = EsclClient(host: p.host);
    final caps = await client.capabilities();
    if (caps == null || !caps.supportsJpeg || _disposed) return;
    p.scanner = ScannerRef(id: 'host:${p.host}', name: caps.model, client: client, caps: caps);
    _notify();
  }

  /// Ручне додавання принтера за IP (коли mDNS мовчить).
  Future<void> addManual(String host) async {
    final p = DiscoveredPrinter(
      id: 'manual:$host',
      name: host,
      host: host,
      port: 631,
      path: 'ipp/print',
      tls: false,
      txt: const {},
      lastSeen: DateTime.now().add(const Duration(days: 3650)), // ручні не забуваємо
    );
    _printers[p.id] = p;
    await refreshCapabilities(p);
    final model = p.capabilities?.model;
    if (model != null) p.name = model;
    _remember(p, manual: true);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    PlatformBridge.stopPrinterDiscovery();
    super.dispose();
  }
}

class _Found {
  final String name, host;
  final int port;
  final bool tls;
  final Map<String, String> txt;
  _Found({required this.name, required this.host, required this.port, required this.tls, required this.txt});
}

