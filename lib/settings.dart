// Запам'ятовані налаштування: останній принтер, колір/дуплекс для кожного принтера,
// макет окремо для документів і фото. Зберігаються в settings.json поруч із printers.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'printing/compose.dart';

class PrinterPrefs {
  final bool color;
  final bool duplex;
  const PrinterPrefs({required this.color, required this.duplex});

  Map<String, dynamic> toJson() => {'color': color, 'duplex': duplex};

  factory PrinterPrefs.fromJson(Map<String, dynamic> j) =>
      PrinterPrefs(color: j['color'] as bool? ?? true, duplex: j['duplex'] as bool? ?? false);
}

class KamiSettings {
  KamiSettings({
    this.lastPrinterId,
    Map<String, PrinterPrefs>? printers,
    this.documentLayout,
    this.photoLayout,
    this.autoOpenShared = false,
    this.lastPrinterFirst = false,
    this.rememberLayout = false,
    this.layoutHintShown = false,
    Map<String, int>? layoutStreak,
    this.checkUpdates = true,
    this.lastUpdateCheck,
    this.scanColor,
    this.scanDpi,
  })  : printers = printers ?? {},
        layoutStreak = layoutStreak ?? {};

  // Перемикачі на екрані налаштувань. Типово вимкнені (крім перевірки оновлень).
  bool autoOpenShared; // файл із «Поділитися» одразу відкриває аркуш друку
  bool lastPrinterFirst; // останній принтер — першим у списку
  bool rememberLayout; // відкривати з макетом минулого друку
  bool checkUpdates; // раз на добу дивитися нову версію на GitHub (виняток: типово увімкнено)
  DateTime? lastUpdateCheck;
  String? scanColor; // останні налаштування сканування (ScanColor.name), пам'ятаємо завжди
  int? scanDpi;

  String? lastPrinterId;
  final Map<String, PrinterPrefs> printers;
  // Останній макет пам'ятаємо завжди, а застосовуємо лише з rememberLayout.
  LayoutOptions? documentLayout;
  LayoutOptions? photoLayout;

  /// Скільки разів поспіль друкували з тим самим нетиповим макетом ('document' / 'photo').
  final Map<String, int> layoutStreak;
  bool layoutHintShown; // підказку «запам'ятовувати макет?» показуємо лише раз

  static const _hintAfter = 2;

  /// Час підказати, що макет можна запам'ятовувати: людина знову вручну виставила той самий.
  bool shouldHintLayout({required bool document}) =>
      !rememberLayout && !layoutHintShown && (layoutStreak[_kind(document)] ?? 0) >= _hintAfter;

  static String _kind(bool document) => document ? 'document' : 'photo';

  static LayoutOptions _defaultLayout(bool document) =>
      document ? const LayoutOptions() : const LayoutOptions(marginMm: 5);

  /// Макет за замовчуванням: документи мають власні поля; фото без полів обріжеться краєм принтера.
  LayoutOptions layoutFor({required bool document}) =>
      (rememberLayout ? (document ? documentLayout : photoLayout) : null) ?? _defaultLayout(document);

  /// Запам'ятати те, чим щойно друкували. Без [layout] (тестова сторінка) макет не чіпаємо.
  void remember({
    required String printerId,
    required PrinterPrefs prefs,
    bool document = true,
    LayoutOptions? layout,
  }) {
    lastPrinterId = printerId;
    printers[printerId] = prefs;
    if (layout != null) {
      final key = layoutToJson(layout).toString();
      final prev = document ? documentLayout : photoLayout;
      final kind = _kind(document);
      if (key == layoutToJson(_defaultLayout(document)).toString()) {
        layoutStreak[kind] = 0;
      } else if (prev != null && key == layoutToJson(prev).toString()) {
        layoutStreak[kind] = (layoutStreak[kind] ?? 0) + 1;
      } else {
        layoutStreak[kind] = 1;
      }
      if (document) {
        documentLayout = layout;
      } else {
        photoLayout = layout;
      }
    }
    save();
  }

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/settings.json');

  static Future<KamiSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return KamiSettings();
      return KamiSettings.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Не вдалося прочитати налаштування: $e');
      return KamiSettings();
    }
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(toJson()));
    } catch (e) {
      debugPrint('Не вдалося зберегти налаштування: $e');
    }
  }

  Map<String, dynamic> toJson() => {
        'autoOpenShared': autoOpenShared,
        'lastPrinterFirst': lastPrinterFirst,
        'rememberLayout': rememberLayout,
        'layoutHintShown': layoutHintShown,
        'layoutStreak': layoutStreak,
        'checkUpdates': checkUpdates,
        'lastUpdateCheck': lastUpdateCheck?.toIso8601String(),
        'scanColor': scanColor,
        'scanDpi': scanDpi,
        'lastPrinterId': lastPrinterId,
        'printers': printers.map((id, p) => MapEntry(id, p.toJson())),
        'documentLayout': documentLayout == null ? null : layoutToJson(documentLayout!),
        'photoLayout': photoLayout == null ? null : layoutToJson(photoLayout!),
      };

  factory KamiSettings.fromJson(Map<String, dynamic> j) {
    LayoutOptions? layout(Object? raw) => raw is Map<String, dynamic> ? layoutFromJson(raw) : null;
    final printers = (j['printers'] as Map<String, dynamic>? ?? {})
        .map((id, raw) => MapEntry(id, PrinterPrefs.fromJson(raw as Map<String, dynamic>)));
    return KamiSettings(
      lastPrinterId: j['lastPrinterId'] as String?,
      printers: printers,
      documentLayout: layout(j['documentLayout']),
      photoLayout: layout(j['photoLayout']),
      autoOpenShared: j['autoOpenShared'] as bool? ?? false,
      lastPrinterFirst: j['lastPrinterFirst'] as bool? ?? false,
      rememberLayout: j['rememberLayout'] as bool? ?? false,
      layoutHintShown: j['layoutHintShown'] as bool? ?? false,
      checkUpdates: j['checkUpdates'] as bool? ?? true,
      lastUpdateCheck: DateTime.tryParse(j['lastUpdateCheck'] as String? ?? ''),
      scanColor: j['scanColor'] as String?,
      scanDpi: j['scanDpi'] as int?,
      layoutStreak: (j['layoutStreak'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v as int)),
    );
  }
}

Map<String, dynamic> layoutToJson(LayoutOptions o) => {
      'orientation': o.orientation.name,
      'scale': o.scale.name,
      'customPercent': o.customPercent,
      'marginMm': o.marginMm,
      'anchor': o.anchor.name,
      'photoSize': o.photoSize?.label,
      'borderless': o.borderless,
    };

/// Невідомі значення (напр. зі старішої версії) тихо замінюються типовими.
LayoutOptions layoutFromJson(Map<String, dynamic> j) {
  T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);
  const d = LayoutOptions();
  final photoLabel = j['photoSize'] as String?;
  return LayoutOptions(
    orientation: byName(LayoutOrientation.values, j['orientation'], d.orientation),
    scale: byName(LayoutScale.values, j['scale'], d.scale),
    customPercent: (j['customPercent'] as num?)?.toDouble() ?? d.customPercent,
    marginMm: (j['marginMm'] as num?)?.toDouble() ?? d.marginMm,
    anchor: byName(LayoutAnchor.values, j['anchor'], d.anchor),
    photoSize: PhotoSize.all.where((p) => p.label == photoLabel).firstOrNull,
    borderless: j['borderless'] as bool? ?? false,
  );
}
