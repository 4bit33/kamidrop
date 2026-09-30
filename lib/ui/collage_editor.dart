import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../printing/collage.dart';
import '../printing/compose.dart';
import '../printing/sources.dart';
import '../theme.dart';

/// Розміри за довгим боком: те, що люди звикли називати «9×13», «10×15», «13×18».
const _sizes = [('9×13', 127.0), ('10×15', 152.0), ('13×18', 178.0)];

/// Редактор «на мінімалках»: кілька фото на аркушах A4. Тягни — щоб перемістити,
/// двома пальцями — щоб змінити розмір. Усе в мм, тож на папері буде рівно так само.
class CollageEditorScreen extends StatefulWidget {
  const CollageEditorScreen({
    super.key,
    required this.source,
    required this.thumbs,
    this.printerMargins = SheetMargins.zero,
    this.onAddPhotos,
  });

  final CollageSource source;
  final List<ui.Image> thumbs; // превʼю фото, за індексом у source.photos
  final SheetMargins printerMargins;

  /// Додати ще фото: відкриває вибір і повертає нові фото з превʼю (або порожньо).
  final Future<List<(ImageSource, ui.Image)>> Function()? onAddPhotos;

  @override
  State<CollageEditorScreen> createState() => _CollageEditorScreenState();
}

class _CollageEditorScreenState extends State<CollageEditorScreen> {
  Collage get collage => widget.source.collage;
  int _sheet = 0;
  CollageItem? _selected;

  // Стан жесту.
  CollageItem? _dragging;
  Offset _startFocal = Offset.zero;
  late double _x0, _y0, _w0, _h0;

  List<CollageItem> get _items => collage.sheets[_sheet];

  /// Вибране фото — нагору, щоб його було видно цілком.
  void _select(CollageItem? item) {
    _selected = item;
    if (item != null && _items.remove(item)) _items.add(item);
  }

  CollageItem? _hit(Offset mm) {
    for (final item in _items.reversed) {
      if (mm.dx >= item.x && mm.dx <= item.right && mm.dy >= item.y && mm.dy <= item.bottom) return item;
    }
    return null;
  }

  void _clamp(CollageItem item) {
    item.x = item.x.clamp(0, math.max(0, a4WidthMm - item.w));
    item.y = item.y.clamp(0, math.max(0, a4HeightMm - item.h));
  }

  /// Змінює розмір, зберігаючи пропорції фото й центр рамки; не більше за аркуш.
  void _resize(CollageItem item, double w, double h, {double? cx, double? cy}) {
    final k = math.min(1.0, math.min(a4WidthMm / w, a4HeightMm / h));
    w *= k;
    h *= k;
    if (math.max(w, h) < 20) return; // дрібніше за 2 см — навряд чи потрібно
    cx ??= item.x + item.w / 2;
    cy ??= item.y + item.h / 2;
    item
      ..w = w
      ..h = h
      ..x = cx - w / 2
      ..y = cy - h / 2;
    _clamp(item);
  }

  void _rotate(CollageItem item) {
    setState(() {
      item.quarterTurns = (item.quarterTurns + 1) % 4;
      _resize(item, item.h, item.w);
    });
  }

  void _setLongSide(CollageItem item, double longSide) {
    final (w, h) = frameForLongSide(collage.aspectOf(item), longSide);
    setState(() => _resize(item, w, h));
  }

  void _duplicate(CollageItem item) {
    final copy = item.copy();
    final spot = findFreeSpot(_items, copy.w, copy.h);
    if (spot != null) {
      copy
        ..x = spot.$1
        ..y = spot.$2;
    } else {
      copy
        ..x = item.x + 5
        ..y = item.y + 5;
      _clamp(copy);
    }
    setState(() {
      _items.add(copy);
      _selected = copy;
    });
  }

  void _delete(CollageItem item) {
    setState(() {
      _items.remove(item);
      _selected = null;
      if (_items.isEmpty && collage.sheets.length > 1) {
        collage.sheets.removeAt(_sheet);
        _sheet = math.min(_sheet, collage.sheets.length - 1);
      }
    });
  }

  void _addSheet() {
    setState(() {
      collage.sheets.add([]);
      _sheet = collage.sheets.length - 1;
      _selected = null;
    });
  }

  Future<void> _addPhotos() async {
    final add = widget.onAddPhotos;
    if (add == null) return;
    final added = await add();
    if (!mounted || added.isEmpty) return;
    setState(() {
      for (final (photo, thumb) in added) {
        widget.source.photos.add(photo);
        widget.thumbs.add(thumb);
        collage.photoSizes.add((photo.pageSize(0).width, photo.pageSize(0).height));
        final item = CollageItem(photo: widget.source.photos.length - 1, x: 0, y: 0, w: 1, h: 1);
        final (w, h) = frameForLongSide(collage.aspectOf(item), 152);
        item
          ..w = w
          ..h = h;
        var spot = findFreeSpot(_items, w, h);
        if (spot == null) {
          collage.sheets.add([]);
          _sheet = collage.sheets.length - 1;
          spot = findFreeSpot(_items, w, h) ?? (5.0, 5.0);
        }
        item
          ..x = spot.$1
          ..y = spot.$2;
        _items.add(item);
        _selected = item;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sel = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Аркуш із фото'),
        actions: [
          if (widget.onAddPhotos != null)
            IconButton(onPressed: _addPhotos, icon: const Icon(Icons.add_photo_alternate_outlined), tooltip: 'Додати фото'),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Готово')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: a4WidthMm / a4HeightMm,
                    child: LayoutBuilder(builder: (context, box) {
                      final k = box.maxWidth / a4WidthMm; // пікселів екрана на мм
                      Offset toMm(Offset p) => p / k;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => setState(() => _select(_hit(toMm(d.localPosition)))),
                        onScaleStart: (d) {
                          final item = _hit(toMm(d.localFocalPoint));
                          setState(() {
                            _dragging = item;
                            if (item != null) _select(item);
                          });
                          if (item == null) return;
                          _startFocal = d.localFocalPoint;
                          _x0 = item.x;
                          _y0 = item.y;
                          _w0 = item.w;
                          _h0 = item.h;
                        },
                        onScaleUpdate: (d) {
                          final item = _dragging;
                          if (item == null) return;
                          final delta = (d.localFocalPoint - _startFocal) / k;
                          setState(() {
                            _resize(item, _w0 * d.scale, _h0 * d.scale,
                                cx: _x0 + _w0 / 2 + delta.dx, cy: _y0 + _h0 / 2 + delta.dy);
                          });
                        },
                        onScaleEnd: (_) => _dragging = null,
                        child: CustomPaint(
                          painter: _CollagePainter(
                            collage: collage,
                            items: _items,
                            thumbs: widget.thumbs,
                            selected: sel,
                            margins: widget.printerMargins,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            if (sel != null) ...[
              Text(
                '${_cm(sel.w)} × ${_cm(sel.h)} см',
                style: theme.textTheme.bodySmall?.copyWith(color: Kami.shu),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    IconButton(onPressed: () => _rotate(sel), icon: const Icon(Icons.rotate_90_degrees_cw), tooltip: 'Повернути'),
                    for (final (label, mm) in _sizes)
                      ChoiceChip(
                        label: Text(label),
                        selected: (math.max(sel.w, sel.h) - mm).abs() < 0.5,
                        showCheckmark: false,
                        selectedColor: Kami.shu.withValues(alpha: 0.15),
                        onSelected: (_) => _setLongSide(sel, mm),
                      ),
                    IconButton(onPressed: () => _duplicate(sel), icon: const Icon(Icons.copy_outlined), tooltip: 'Копія'),
                    IconButton(
                        onPressed: () => _delete(sel), icon: const Icon(Icons.delete_outline), tooltip: 'Прибрати'),
                  ],
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _sheet > 0 ? () => setState(() => _sheet--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Аркуш ${_sheet + 1} з ${collage.sheets.length}', style: theme.textTheme.bodySmall),
                    IconButton(
                      onPressed: _sheet < collage.sheets.length - 1 ? () => setState(() => _sheet++) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _addSheet,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Аркуш'),
                      style: TextButton.styleFrom(foregroundColor: Kami.stone),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _cm(double mm) => (mm / 10).toStringAsFixed(1).replaceAll('.', ',');

class _CollagePainter extends CustomPainter {
  _CollagePainter({
    required this.collage,
    required this.items,
    required this.thumbs,
    required this.selected,
    required this.margins,
  });

  final Collage collage;
  final List<CollageItem> items;
  final List<ui.Image> thumbs;
  final CollageItem? selected;
  final SheetMargins margins;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / a4WidthMm;
    final sheet = Offset.zero & size;
    canvas.drawRect(sheet.shift(const Offset(0, 2)), Paint()..color = Kami.sumi.withValues(alpha: 0.08));
    canvas.drawRect(sheet, Paint()..color = Colors.white);

    for (final item in items) {
      final frame = Rect.fromLTWH(item.x * k, item.y * k, item.w * k, item.h * k);
      final (cx, cy, cw, ch) = contentRect(item, collage.aspectOf(item), scale: k);
      final img = thumbs[item.photo];
      canvas.save();
      canvas.clipRect(frame);
      // Малюємо фото повернутим навколо центру вмісту.
      canvas.translate(cx + cw / 2, cy + ch / 2);
      canvas.rotate(item.quarterTurns * math.pi / 2);
      final (dw, dh) = item.quarterTurns.isOdd ? (ch, cw) : (cw, ch);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: dw, height: dh),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }

    // Смуга, куди принтер не дістає (поверх фото — видно, що там обріжеться).
    if (!margins.isZero) {
      final safe = Rect.fromLTRB(
          margins.left * k, margins.top * k, size.width - margins.right * k, size.height - margins.bottom * k);
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(sheet)
          ..addRect(safe),
        Paint()..color = Kami.line.withValues(alpha: 0.7),
      );
    }
    canvas.drawRect(sheet, Paint()
      ..color = Kami.line
      ..style = PaintingStyle.stroke);

    final sel = selected;
    if (sel != null && items.contains(sel)) {
      canvas.drawRect(
        Rect.fromLTWH(sel.x * k, sel.y * k, sel.w * k, sel.h * k),
        Paint()
          ..color = Kami.shu
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CollagePainter old) => true;
}
