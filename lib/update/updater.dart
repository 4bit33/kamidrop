// Оновлення з GitHub-релізів: перевірка останньої версії й завантаження APK.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const releasesRepo = '4bit33/kamidrop';

class UpdateInfo {
  final String version; // без «v»
  final String notes;
  final String apkUrl;
  final int apkSize;
  const UpdateInfo({required this.version, required this.notes, required this.apkUrl, required this.apkSize});
}

/// «v0.1.2» / «0.1.2+5» → [0, 1, 2]. Нечислові частини — 0.
List<int> parseVersion(String v) {
  final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[+\-]')).first;
  return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
}

/// true, якщо [candidate] новіша за [current].
bool isNewer(String candidate, String current) {
  final a = parseVersion(candidate), b = parseVersion(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Розбирає відповідь GitHub `releases/latest`. APK обирається під архітектуру [abi]
/// (напр. «arm64-v8a»), або універсальний, якщо окремого немає. null — APK немає.
UpdateInfo? parseRelease(Map<String, dynamic> json, {required String abi}) {
  final tag = json['tag_name'] as String? ?? '';
  final assets = (json['assets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()
      .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
      .toList();
  if (tag.isEmpty || assets.isEmpty) return null;
  Map<String, dynamic>? pick(bool Function(String name) test) =>
      assets.where((a) => test(a['name'] as String)).firstOrNull;
  final abiNames = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  final asset = pick((n) => abi.isNotEmpty && n.contains(abi)) ??
      pick((n) => !abiNames.any(n.contains)) ?? // універсальний
      pick((n) => n.contains('arm64-v8a'));
  if (asset == null) return null;
  return UpdateInfo(
    version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
    notes: json['body'] as String? ?? '',
    apkUrl: asset['browser_download_url'] as String,
    apkSize: (asset['size'] as num?)?.toInt() ?? 0,
  );
}

/// Остання версія з GitHub, якщо вона новіша за [currentVersion]; інакше null.
Future<UpdateInfo?> checkForUpdate({required String currentVersion, required String abi}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'));
    req.headers
      ..set(HttpHeaders.userAgentHeader, 'KamiDrop/$currentVersion')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close().timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return null; // 404 — релізів ще немає
    }
    final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final info = parseRelease(json, abi: abi);
    return info != null && isNewer(info.version, currentVersion) ? info : null;
  } finally {
    client.close(force: true);
  }
}

/// Завантажує APK у кеш, звітуючи [onProgress] (0…1). Повертає шлях до файлу.
Future<String> downloadUpdate(UpdateInfo info, {void Function(double)? onProgress}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/update');
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final file = File('${dir.path}/kamidrop-${info.version}.apk');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final resp = await (await client.getUrl(Uri.parse(info.apkUrl))).close(); // GitHub перенаправляє — це ок
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final total = resp.contentLength > 0 ? resp.contentLength : info.apkSize;
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in resp) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
    }
    await sink.close();
    return file.path;
  } finally {
    client.close(force: true);
  }
}
