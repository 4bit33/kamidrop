import '../ipp/ipp.dart';
import 'urf.dart';

/// Витратний матеріал (картридж/тонер) з атрибутів marker-*.
class Marker {
  final String name;
  final String color; // #RRGGBB
  final int level; // 0..100, або <0 якщо невідомо
  final int lowLevel;
  final String type;

  const Marker({required this.name, required this.color, required this.level, required this.lowLevel, required this.type});

  bool get isLow => level >= 0 && level <= lowLevel;
}

enum PrinterState { idle, processing, stopped, unknown }

/// Те, що принтер уміє, — зведено з відповіді Get-Printer-Attributes і mDNS TXT.
class PrinterCapabilities {
  final String model;
  final PrinterState state;
  final String? stateMessage;
  final List<String> formats;
  final List<String> urf;
  final List<int> urfResolutions;
  final bool supportsColor;
  final bool supportsDuplex;
  final bool supportsLandscape;
  final SheetBack sheetBack;
  final bool printerHandlesCopies;
  final int maxCopies;
  final List<String> media;
  final List<Marker> markers;

  const PrinterCapabilities({
    required this.model,
    required this.state,
    required this.stateMessage,
    required this.formats,
    required this.urf,
    required this.urfResolutions,
    required this.supportsColor,
    required this.supportsDuplex,
    required this.supportsLandscape,
    required this.sheetBack,
    required this.printerHandlesCopies,
    required this.maxCopies,
    required this.media,
    required this.markers,
  });

  bool get supportsUrf => formats.contains('image/urf');

  /// Найменша підтримувана роздільність — достатньо для документів і найшвидше.
  int get defaultDpi => urfResolutions.isEmpty ? 300 : urfResolutions.reduce((a, b) => a < b ? a : b);

  factory PrinterCapabilities.fromIpp(IppResponse r, {Map<String, String> txt = const {}}) {
    final urf = r.all<String>('urf-supported');
    final urfList = urf.isNotEmpty ? urf : (txt['urf']?.split(',') ?? const <String>[]);

    final dpis = <int>{};
    for (final item in urfList) {
      if (item.startsWith('RS')) {
        for (final part in item.substring(2).split('-')) {
          final v = int.tryParse(part);
          if (v != null) dpis.add(v);
        }
      }
    }

    var dm = 1;
    for (final item in urfList) {
      if (item.startsWith('DM')) dm = int.tryParse(item.substring(2)) ?? 1;
    }
    final sheetBack = switch (dm) {
      2 => SheetBack.flipped,
      3 => SheetBack.rotated,
      4 => SheetBack.manualTumble,
      _ => SheetBack.normal,
    };

    final stateCode = r.first<int>('printer-state');
    final state = switch (stateCode) {
      3 => PrinterState.idle,
      4 => PrinterState.processing,
      5 => PrinterState.stopped,
      _ => PrinterState.unknown,
    };

    final copiesRange = r.first<IppRange>('copies-supported');
    final creation = r.all<String>('job-creation-attributes-supported');
    final txtCopies = txt['copies'];

    final names = r.all<String>('marker-names');
    final colors = r.all<String>('marker-colors');
    final levels = r.all<int>('marker-levels');
    final lows = r.all<int>('marker-low-levels');
    final types = r.all<String>('marker-types');
    final markers = <Marker>[
      for (var i = 0; i < names.length && i < levels.length; i++)
        Marker(
          name: names[i],
          color: i < colors.length ? colors[i] : '#000000',
          level: levels[i],
          lowLevel: i < lows.length ? lows[i] : 10,
          type: i < types.length ? types[i] : '',
        ),
    ];

    final sides = r.all<String>('sides-supported');
    final colorModes = r.all<String>('print-color-mode-supported');

    return PrinterCapabilities(
      model: r.first<String>('printer-make-and-model') ?? txt['ty'] ?? 'Невідомий принтер',
      state: state,
      stateMessage: r.first<String>('printer-state-message'),
      formats: r.all<String>('document-format-supported'),
      urf: urfList,
      urfResolutions: dpis.toList()..sort(),
      supportsColor: urfList.contains('SRGB24') && (colorModes.isEmpty || colorModes.contains('color')),
      supportsDuplex: sides.any((s) => s.startsWith('two-sided')),
      supportsLandscape: r.all<int>('orientation-requested-supported').contains(4),
      sheetBack: sheetBack,
      printerHandlesCopies: creation.contains('copies') && txtCopies != 'F',
      maxCopies: copiesRange?.upper ?? 1,
      media: r.all<String>('media-supported'),
      markers: markers,
    );
  }
}
