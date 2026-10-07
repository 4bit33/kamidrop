import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../printing/collage.dart';
import '../printing/compose.dart';
import '../printing/sources.dart';
import '../theme.dart';
import '../l10n/l10n.dart';

/// Точні розміри фото (короткий × довгий бік, мм) — як у PhotoSize.
const _sizes = [('9×13', 89.0, 127.0), ('10×15', 102.0, 152.0), ('13×18', 127.0, 178.0)];

/// Свайп, після якого гортаємо аркуш (пікселі екрана).
const _swipe = 60.0;

enum _Mode { none, drag, pinch, carry, cropPan, cropZoom, swipe, ignore }

/// Редактор «на мінімалках»: кілька фото на аркушах A4. Усе в мм, тож на папері буде рівно так само.
///  - один палець на фото — тягнути; два — масштаб;
///  - тримати фото й свайпнути іншим пальцем — перенести на сусідній аркуш;
///  - свайп по порожньому місцю — сусідній аркуш;
///  - подвійний тап — кадрування: палець рухає фото в рамці, два пальці — наближення.
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
  CollageItem? _cropping; // фото в режимі кадрування

  // Стан жесту.
  double _k = 1; // пікселів екрана на мм
  final _pos = <int, Offset>{}, _start = <int, Offset>{};
  _Mode _mode = _Mode.none;
  int? _first, _second;
  CollageItem? _target;
  double _x0 = 0, _y0 = 0, _w0 = 0, _h0 = 0, _zoom0 = 1, _panX0 = 0, _panY0 = 0, _dist0 = 1;
  Offset _mid0 = Offset.zero;
  bool _carried = false;
  DateTime? _lastTapAt;
  CollageItem? _lastTapItem;

  List<CollageItem> get _items => collage.sheets[_sheet];

  /// Вибране фото — нагору, щоб його було видно цілком.
  void _select(CollageItem? item) {
    _selected = item;
    if (_cropping != item) _cropping = null;
    if (item != null && _items.remove(item)) _items.add(item);
  }

  CollageItem? _hit(Offset mm) {
    for (final item in _items.reversed) {
      if (_contains(item, mm)) return item;
    }
    return null;
  }

  bool _contains(CollageItem item, Offset mm) =>
      mm.dx >= item.x && mm.dx <= item.right && mm.dy >= item.y && mm.dy <= item.bottom;

  void _clamp(CollageItem item) {
    item.x = item.x.clamp(0, math.max(0, a4WidthMm - item.w));
    item.y = item.y.clamp(0, math.max(0, a4HeightMm - item.h));
  }

  /// Змінює розмір рамки (пропорції задає виклик) навколо центру; не більше за аркуш.
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

  // ---------------------------------------------------------------- жести

  void _down(PointerDownEvent e) {
    _pos[e.pointer] = e.localPosition;
    _start[e.pointer] = e.localPosition;
    final mm = e.localPosition / _k;
    if (_pos.length == 1) {
      _first = e.pointer;
      _carried = false;
      final hit = _hit(mm);
      setState(() {
        if (hit != null && hit == _cropping) {
          _mode = _Mode.cropPan;
          _target = hit;
          _panX0 = hit.panX;
          _panY0 = hit.panY;
        } else if (hit != null) {
          _mode = _Mode.drag;
          _target = hit;
          _select(hit);
          _x0 = hit.x;
          _y0 = hit.y;
        } else {
          _mode = _Mode.swipe;
          _target = null;
        }
      });
    } else if (_pos.length == 2) {
      _second = e.pointer;
      final t = _target;
      final p1 = _pos[_first]!, p2 = e.localPosition;
      _dist0 = math.max(1, (p1 - p2).distance);
      _mid0 = (p1 + p2) / 2;
      if (_mode == _Mode.drag && t != null) {
        _w0 = t.w;
        _h0 = t.h;
        _x0 = t.x;
        _y0 = t.y;
        // Другий палець на тому ж фото — масштаб; поза ним — «нести» фото на інший аркуш.
        _mode = _contains(t, mm) ? _Mode.pinch : _Mode.carry;
      } else if (_mode == _Mode.cropPan && t != null) {
        _zoom0 = t.zoom;
        _mode = _Mode.cropZoom;
      } else {
        _mode = _Mode.ignore;
      }
    } else {
      _mode = _Mode.ignore;
    }
  }

  void _move(PointerMoveEvent e) {
    _pos[e.pointer] = e.localPosition;
    final t = _target;
    switch (_mode) {
      case _Mode.drag when t != null && e.pointer == _first:
        final d = (e.localPosition - _start[_first]!) / _k;
        setState(() {
          t
            ..x = _x0 + d.dx
            ..y = _y0 + d.dy;
          _clamp(t);
        });
      case _Mode.pinch when t != null:
        final p1 = _pos[_first]!, p2 = _pos[_second]!;
        final s = (p1 - p2).distance / _dist0;
        final dm = ((p1 + p2) / 2 - _mid0) / _k;
        setState(() => _resize(t, _w0 * s, _h0 * s, cx: _x0 + _w0 / 2 + dm.dx, cy: _y0 + _h0 / 2 + dm.dy));
      case _Mode.carry when t != null && e.pointer == _second && !_carried:
        final dx = e.localPosition.dx - _start[_second]!.dx;
        if (dx.abs() > _swipe) {
          _carried = true; // один свайп — один аркуш
          _moveToSheet(t, dx < 0 ? 1 : -1);
        }
      case _Mode.cropPan when t != null && e.pointer == _first:
        final d = (e.localPosition - _start[_first]!) / _k;
        setState(() => panBy(t, collage.aspectOf(t), d.dx, d.dy, _panX0, _panY0));
      case _Mode.cropZoom when t != null:
        final s = (_pos[_first]! - _pos[_second]!).distance / _dist0;
        setState(() {
          t.zoom = (_zoom0 * s).clamp(1.0, 5.0);
          panBy(t, collage.aspectOf(t), 0, 0, t.panX, t.panY); // pan у нових межах
        });
      default:
    }
  }

  void _up(PointerEvent e) {
    final start = _start[e.pointer], pos = _pos[e.pointer];
    if (start != null && pos != null && e.pointer == _first && _pos.length == 1) {
      final d = pos - start;
      if (_mode == _Mode.swipe) {
        if (d.dx.abs() > _swipe && d.dx.abs() > d.dy.abs() * 1.5) {
          _goToSheet(_sheet + (d.dx < 0 ? 1 : -1));
        } else if (d.distance < 10) {
          setState(() => _select(null)); // тап по порожньому
        }
      } else if (_mode == _Mode.drag && d.distance < 10) {
        _tapOn(_target);
      }
    }
    _pos.remove(e.pointer);
    _start.remove(e.pointer);
    if (_pos.isEmpty) {
      _mode = _Mode.none;
      _target = null;
    } else if (_mode != _Mode.drag && _mode != _Mode.cropPan) {
      _mode = _Mode.ignore; // після двох пальців — чекаємо, поки приберуть усі
    }
  }

  /// Подвійний тап по фото — увімкнути/вимкнути кадрування.
  void _tapOn(CollageItem? item) {
    final now = DateTime.now();
    final isDouble = item != null &&
        item == _lastTapItem &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < const Duration(milliseconds: 350);
    if (isDouble) {
      setState(() => _cropping = _cropping == item ? null : item);
      _lastTapItem = null;
    } else {
      _lastTapItem = item;
      _lastTapAt = now;
    }
  }

  void _goToSheet(int index) {
    if (index < 0 || index >= collage.sheets.length) return;
    setState(() {
      _sheet = index;
      _select(null);
    });
  }

  /// Переносить фото на сусідній аркуш (за останнім — створює новий), на те саме місце.
  void _moveToSheet(CollageItem item, int dir) {
    final to = _sheet + dir;
    if (to < 0) {
      _toast(l10n.firstSheet);
      return;
    }
    setState(() {
      if (to >= collage.sheets.length) collage.sheets.add([]);
      _items.remove(item);
      _sheet = to;
      _items.add(item);
      _clamp(item);
      _selected = item;
      _cropping = null;
    });
    _toast(l10n.photoOnSheet(to + 1));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1200)));
  }

  // ---------------------------------------------------------------- дії

  void _rotate(CollageItem item) {
    setState(() {
      item.quarterTurns = (item.quarterTurns + 1) % 4;
      _resize(item, item.h, item.w);
    });
  }

  void _setExact(CollageItem item, double shortMm, double longMm) {
    setState(() {
      setExactFrame(item, collage.aspectOf(item), shortMm, longMm);
      _clamp(item);
    });
  }

  /// «Ціле» — рамка з пропорціями фото, без обрізки, той самий довгий бік.
  void _setWhole(CollageItem item) {
    final (w, h) = frameForLongSide(collage.aspectOf(item), math.max(item.w, item.h));
    setState(() {
      item
        ..zoom = 1
        ..panX = 0
        ..panY = 0;
      _resize(item, w, h);
      _cropping = null;
    });
  }

  bool _isWhole(CollageItem item) =>
      item.zoom == 1 && ((item.w / item.h) - collage.aspectOf(item)).abs() < 0.01;

  bool _isExact(CollageItem item, double shortMm, double longMm) {
    bool near(double a, double b) => (a - b).abs() < 0.5;
    return (near(item.w, longMm) && near(item.h, shortMm)) || (near(item.w, shortMm) && near(item.h, longMm));
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
      _select(copy);
    });
  }

  void _delete(CollageItem item) {
    setState(() {
      _items.remove(item);
      _select(null);
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
      _select(null);
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
        _select(item);
      }
    });
  }

  // ---------------------------------------------------------------- вигляд

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final sel = _selected;
    final crop = _cropping;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.collageTitle),
        actions: [
          if (widget.onAddPhotos != null)
            IconButton(onPressed: _addPhotos, icon: const Icon(Icons.add_photo_alternate_outlined), tooltip: l10n.addPhotos),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.done)),
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
                      _k = box.maxWidth / a4WidthMm;
                      return Listener(
                        key: const ValueKey('collage-sheet'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _down,
                        onPointerMove: _move,
                        onPointerUp: _up,
                        onPointerCancel: _up,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _CollagePainter(
                            collage: collage,
                            items: _items,
                            thumbs: widget.thumbs,
                            selected: sel,
                            cropping: crop,
                            margins: widget.printerMargins,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            // Фіксована висота: аркуш не стрибає, коли вибираєш фото (інакше жест «з'їжджає»).
            SizedBox(
              height: 132,
              child: crop != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(l10n.cropHint, style: small),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(onPressed: () => _setWhole(crop), child: Text(l10n.noCrop)),
                            const SizedBox(width: 8),
                            FilledButton(
                                onPressed: () => setState(() => _cropping = null), child: Text(l10n.done)),
                          ],
                        ),
                      ],
                    )
                  : sel != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(l10n.sizeCm(_cm(sel.w), _cm(sel.h)), style: small?.copyWith(color: Kami.shu)),
                            const SizedBox(height: 4),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  IconButton(
                                      onPressed: () => _rotate(sel),
                                      icon: const Icon(Icons.rotate_90_degrees_cw),
                                      tooltip: l10n.rotate),
                                  _chip(l10n.whole, _isWhole(sel), () => _setWhole(sel)),
                                  for (final (label, s, l) in _sizes)
                                    _chip(label, _isExact(sel, s, l), () => _setExact(sel, s, l)),
                                  IconButton(
                                      onPressed: () => _duplicate(sel),
                                      icon: const Icon(Icons.copy_outlined),
                                      tooltip: l10n.duplicate),
                                  IconButton(
                                      onPressed: () => _delete(sel),
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: l10n.remove),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: Text(
                                l10n.collageHint,
                                style: small?.copyWith(color: Kami.stone),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _sheet > 0 ? () => _goToSheet(_sheet - 1) : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text(l10n.pageOf(l10n.unitSheet, _sheet + 1, collage.sheets.length), style: small),
                            IconButton(
                              onPressed: _sheet < collage.sheets.length - 1 ? () => _goToSheet(_sheet + 1) : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _addSheet,
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(l10n.unitSheet),
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

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ChoiceChip(
          label: Text(label),
        selected: selected,
        showCheckmark: false,
          selectedColor: Kami.shu.withValues(alpha: 0.15),
          onSelected: (_) => onTap(),
        ),
      );
}

String _cm(double mm) => decimal(mm / 10, 1);

class _CollagePainter extends CustomPainter {
  _CollagePainter({
    required this.collage,
    required this.items,
    required this.thumbs,
    required this.selected,
    required this.cropping,
    required this.margins,
  });

  final Collage collage;
  final List<CollageItem> items;
  final List<ui.Image> thumbs;
  final CollageItem? selected;
  final CollageItem? cropping;
  final SheetMargins margins;

  /// Фото повернутим навколо центру вмісту.
  void _drawPhoto(Canvas canvas, CollageItem item, double k, Paint paint) {
    final (cx, cy, cw, ch) = contentRect(item, collage.aspectOf(item), scale: k);
    final img = thumbs[item.photo];
    canvas.save();
    canvas.translate(cx + cw / 2, cy + ch / 2);
    canvas.rotate(item.quarterTurns * math.pi / 2);
    final (dw, dh) = item.quarterTurns.isOdd ? (ch, cw) : (cw, ch);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: dw, height: dh),
      paint,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / a4WidthMm;
    final sheet = Offset.zero & size;
    canvas.drawRect(sheet.shift(const Offset(0, 2)), Paint()..color = Kami.sumi.withValues(alpha: 0.08));
    canvas.drawRect(sheet, Paint()..color = Colors.white);

    final photo = Paint()..filterQuality = FilterQuality.medium;
    for (final item in items) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(item.x * k, item.y * k, item.w * k, item.h * k));
      _drawPhoto(canvas, item, k, photo);
      canvas.restore();
    }

    // Кадрування: те, що обріжеться, — напівпрозоро поверх усього.
    final crop = cropping;
    if (crop != null && items.contains(crop)) {
      canvas.saveLayer(sheet, Paint());
      _drawPhoto(canvas, crop, k, Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0x59000000));
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(crop.x * k, crop.y * k, crop.w * k, crop.h * k));
      _drawPhoto(canvas, crop, k, photo);
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
          ..strokeWidth = sel == crop ? 3 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CollagePainter old) => true;
}
