import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/update/updater.dart';

Map<String, dynamic> _release(String tag, List<String> apks) => {
      'tag_name': tag,
      'body': 'Що нового',
      'assets': [
        for (final n in apks) {'name': n, 'browser_download_url': 'https://example/$n', 'size': 100},
        {'name': 'checksums.txt', 'browser_download_url': 'https://example/c', 'size': 1},
      ],
    };

void main() {
  test('Порівняння версій', () {
    expect(isNewer('v0.1.1', '0.1.0'), isTrue);
    expect(isNewer('0.2.0', '0.10.0'), isFalse, reason: 'числа, а не рядки');
    expect(isNewer('v1.0', '0.9.9'), isTrue);
    expect(isNewer('0.1.0', '0.1.0'), isFalse);
    expect(isNewer('0.1.0+7', '0.1.0'), isFalse, reason: 'номер збірки не робить версію новішою');
    expect(parseVersion('v1.2.3'), [1, 2, 3]);
  });

  test('APK під архітектуру телефона, інакше універсальний', () {
    final split = _release('v0.2.0', [
      'kamidrop-0.2.0-armeabi-v7a.apk',
      'kamidrop-0.2.0-arm64-v8a.apk',
      'kamidrop-0.2.0-x86_64.apk',
    ]);
    final arm64 = parseRelease(split, abi: 'arm64-v8a')!;
    expect(arm64.version, '0.2.0');
    expect(arm64.apkUrl, endsWith('arm64-v8a.apk'));
    expect(parseRelease(split, abi: 'armeabi-v7a')!.apkUrl, endsWith('armeabi-v7a.apk'));

    final universal = _release('v0.2.0', ['kamidrop-0.2.0.apk', 'kamidrop-0.2.0-x86_64.apk']);
    expect(parseRelease(universal, abi: 'arm64-v8a')!.apkUrl, endsWith('kamidrop-0.2.0.apk'));

    expect(parseRelease(_release('v0.2.0', []), abi: 'arm64-v8a'), isNull, reason: 'APK немає');
  });
}
