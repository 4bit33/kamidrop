import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Міст до нативного коду Android (MainActivity.kt): системний пошук принтерів (NsdManager),
/// multicast lock, файли з «Поділитися → KamiDrop» і вибір фото. На інших платформах — нічого не робить.
class PlatformBridge {
  static const _channel = MethodChannel('kamidrop/platform');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static void Function(String path)? _onSharedFile;
  static void Function(String message)? _onUpdateError;
  static void Function(Map<String, Object?> service)? _onPrinterFound;
  static bool _handlerInstalled = false;

  /// Один обробник на канал: він розводить виклики з нативного боку за назвою методу.
  static void _ensureHandler() {
    if (_handlerInstalled || !_isAndroid) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'sharedFile':
          if (args is String) _onSharedFile?.call(args);
        case 'printerFound':
          if (args is Map) _onPrinterFound?.call(Map<String, Object?>.from(args));
        case 'updateError':
          if (args is String) _onUpdateError?.call(args);
      }
    });
  }

  /// На Android пошук принтерів іде через системний NsdManager.
  static bool get hasNativeDiscovery => _isAndroid;

  /// Запускає (або перезапускає) системний пошук. [onFound] отримує name, host, port, tls, txt.
  static Future<void> startPrinterDiscovery(void Function(Map<String, Object?> service) onFound) async {
    if (!_isAndroid) return;
    _onPrinterFound = onFound;
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('startPrinterDiscovery');
    } catch (e) {
      debugPrint('NSD: $e');
    }
  }

  static Future<void> stopPrinterDiscovery() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopPrinterDiscovery');
    } catch (_) {}
  }

  /// Без multicast lock Android відкидає вхідні multicast-пакети (потрібно лише для Dart-mDNS).
  static Future<void> acquireMulticastLock() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } catch (e) {
      debugPrint('multicast lock: $e');
    }
  }

  static Future<void> releaseMulticastLock() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {}
  }

  /// Файл, з яким застосунок запустили (шлях до копії в кеші), або null.
  static Future<String?> takeSharedFile() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeSharedFile');
    } catch (_) {
      return null;
    }
  }

  /// Вибір одного чи кількох фото системним Photo Picker. Шляхи до копій у кеші; порожньо — нічого не вибрали.
  static Future<List<String>> pickImages() async {
    if (!_isAndroid) return const [];
    final paths = await _channel.invokeListMethod<String>('pickImages');
    return paths ?? const [];
  }

  /// Версія застосунку й основна архітектура процесора (для вибору APK). null — не Android.
  static Future<({String version, int code, String abi})?> appInfo() async {
    if (!_isAndroid) return null;
    final m = await _channel.invokeMapMethod<String, Object?>('appInfo');
    if (m == null) return null;
    return (version: m['versionName'] as String, code: (m['versionCode'] as num).toInt(), abi: m['abi'] as String);
  }

  /// Ставить завантажений APK поверх застосунку. 'permission' — спершу треба дозволити
  /// KamiDrop встановлювати застосунки (налаштування вже відкрито), 'started' — пішло.
  static Future<String> installApk(String path) async =>
      await _channel.invokeMethod<String>('installApk', path) ?? 'started';

  /// Помилки встановлення оновлення, що приходять від системи пізніше.
  static void listenUpdateErrors(void Function(String message) onError) {
    if (!_isAndroid) return;
    _onUpdateError = onError;
    _ensureHandler();
  }

  /// Файли, надіслані, коли застосунок уже відкритий.
  static void listenSharedFiles(void Function(String path) onFile) {
    if (!_isAndroid) return;
    _onSharedFile = onFile;
    _ensureHandler();
  }
}
