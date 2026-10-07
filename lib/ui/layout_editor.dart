import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../printing/compose.dart';
import '../printing/sources.dart';
import '../printing/test_page.dart';
import '../theme.dart';
import 'page_pager.dart';
import '../l10n/l10n.dart';

/// Мініредактор макета: превʼю аркуша + орієнтація, розмір, поля, розташування.
class LayoutEditor extends StatelessWidget {
  const LayoutEditor({
    super.key,
    required this.source,
    required this.image,
    required this.index,
    required this.layout,
    required this.onChanged,
    required this.onIndexChanged,
    this.printerMargins = SheetMargins.zero,
    this.canBorderless = false,
    this.enabled = true,
    this.pages,
    this.thumbFor,
  });

  final PrintSource source;
  final ui.Image? image;
  final int index;
  final LayoutOptions layout;
  final ValueChanged<LayoutOptions> onChanged;
  final ValueChanged<int> onIndexChanged;
  final SheetMargins printerMargins;
  final bool canBorderless; // принтер уміє друк «до краю»
  final bool enabled;
  final List<int>? pages; // які сторінки показувати (вибрані для друку); null — усі
  final Future<ui.Image> Function(int page)? thumbFor; // мініатюри для стрічки сторінок

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.bodySmall;
    final photo = layout.photoSize;
    final isCustom = photo == null && layout.scale == LayoutScale.custom;

    void set(LayoutOptions o) {
      if (enabled) onChanged(o);
    }

    Widget chip(String text, bool selected, VoidCallback onTap) => ChoiceChip(
          label: Text(text),
          selected: selected,
          showCheckmark: false,
          selectedColor: Kami.shu.withValues(alpha: 0.15),
          side: BorderSide(color: selected ? Kami.shu : Kami.line),
          onSelected: enabled ? (_) => onTap() : null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PagePager(
          preview: SheetPreview(
            size: source.pageSize(index),
            image: image,
            layout: layout,
            printerMargins: effectiveMargins(layout, printerMargins, printerBorderless: canBorderless),
          ),
          pages: pages ?? List.generate(source.pageCount, (i) => i),
          total: source.pageCount,
          index: index,
          onIndexChanged: onIndexChanged,
          thumbFor: thumbFor ?? (i) => source.preview(i, maxSide: 140),
        ),
        const SizedBox(height: 4),
        Text(l10n.orientation, style: label),
        const SizedBox(height: 6),
        SegmentedButton<LayoutOrientation>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: LayoutOrientation.auto, label: Text(l10n.orientationAuto)),
            ButtonSegment(value: LayoutOrientation.portrait, label: Text(l10n.portrait)),
            ButtonSegment(value: LayoutOrientation.landscape, label: Text(l10n.landscape)),
          ],
          selected: {layout.orientation},
          onSelectionChanged: enabled ? (s) => set(layout.copyWith(orientation: s.first)) : null,
        ),
        const SizedBox(height: 14),
        Text(l10n.size, style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(l10n.fit, photo == null && layout.scale == LayoutScale.fit,
                () => set(layout.copyWith(scale: LayoutScale.fit, clearPhotoSize: true))),
            if (source.isDocument)
              chip('100 %', photo == null && layout.scale == LayoutScale.actual,
                  () => set(layout.copyWith(scale: LayoutScale.actual, clearPhotoSize: true))),
            chip(l10n.fill, photo == null && layout.scale == LayoutScale.fill,
                () => set(layout.copyWith(scale: LayoutScale.fill, clearPhotoSize: true))),
            if (!source.isDocument)
              for (final ps in PhotoSize.all)
                chip(ps.label, photo?.label == ps.label, () => set(layout.copyWith(photoSize: ps))),
            chip(l10n.custom, isCustom, () => set(layout.copyWith(scale: LayoutScale.custom, clearPhotoSize: true))),
          ],
        ),
        if (isCustom)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: layout.customPercent.clamp(10.0, 100.0),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '${layout.customPercent.round()} %',
                  onChanged: enabled ? (v) => set(layout.copyWith(customPercent: v)) : null,
                ),
              ),
              SizedBox(width: 48, child: Text('${layout.customPercent.round()} %', textAlign: TextAlign.right)),
            ],
          ),
        const SizedBox(height: 14),
        Text(l10n.margins, style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            if (canBorderless)
              chip(l10n.edgeToEdge, layout.borderless, () => set(layout.copyWith(marginMm: 0, borderless: true))),
            // «Мінімальні» — впритул до полів, які принтер не друкує.
            for (final (mm, text) in [(0.0, l10n.minimal), (5.0, l10n.mm(5)), (10.0, l10n.mm(10))])
              chip(text, layout.marginMm == mm && !(layout.borderless && canBorderless),
                  () => set(layout.copyWith(marginMm: mm, borderless: false))),
          ],
        ),
        if (photo != null || isCustom) ...[
          const SizedBox(height: 14),
          Text(l10n.placement, style: label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              chip(l10n.centered, layout.anchor == LayoutAnchor.center,
                  () => set(layout.copyWith(anchor: LayoutAnchor.center))),
              chip(l10n.top, layout.anchor == LayoutAnchor.top, () => set(layout.copyWith(anchor: LayoutAnchor.top))),
            ],
          ),
        ],
      ],
    );
  }
}

/// Превʼю аркуша. Використовує той самий computeLayout, що й друк, тож що бачиш — те й друкується.
class SheetPreview extends StatelessWidget {
  const SheetPreview({
    super.key,
    required this.size,
    required this.image,
    required this.layout,
    this.printerMargins = SheetMargins.zero,
  });

  final ContentSize size;
  final ui.Image? image;
  final LayoutOptions layout;
  final SheetMargins printerMargins;

  static const _dpi = 40; // «віртуальна» роздільність превʼю

  @override
  Widget build(BuildContext context) {
    final lay = computeLayout(size, layout,
        pageW: a4WidthPx(_dpi), pageH: a4HeightPx(_dpi), dpi: _dpi, printerMargins: printerMargins);
    return CustomPaint(
      painter: _SheetPainter(lay, image, showCutLines: layout.photoSize != null, showSafeArea: !printerMargins.isZero),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.lay, this.image, {required this.showCutLines, required this.showSafeArea});

  final PageLayout lay;
  final ui.Image? image;
  final bool showCutLines;
  final bool showSafeArea;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (size.width / lay.canvasW) < (size.height / lay.canvasH)
        ? size.width / lay.canvasW
        : size.height / lay.canvasH;
    final sheet = Rect.fromLTWH(
      (size.width - lay.canvasW * s) / 2,
      (size.height - lay.canvasH * s) / 2,
      lay.canvasW * s,
      lay.canvasH * s,
    );
    // Аркуш із легкою тінню.
    canvas.drawRect(sheet.shift(const Offset(0, 2)), Paint()..color = Kami.sumi.withValues(alpha: 0.08));
    canvas.drawRect(sheet, Paint()..color = Colors.white);
    canvas.drawRect(
        sheet,
        Paint()
          ..color = Kami.line
          ..style = PaintingStyle.stroke);

    // Смуга по краю, куди принтер не дістає.
    if (showSafeArea) {
      final safe = Rect.fromLTRB(
        sheet.left + lay.safeX0 * s,
        sheet.top + lay.safeY0 * s,
        sheet.left + lay.safeX1 * s,
        sheet.top + lay.safeY1 * s,
      );
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(sheet)
          ..addRect(safe),
        Paint()..color = Kami.line.withValues(alpha: 0.6),
      );
    }

    final clip = Rect.fromLTRB(
      sheet.left + lay.clipX0 * s,
      sheet.top + lay.clipY0 * s,
      sheet.left + lay.clipX1 * s,
      sheet.top + lay.clipY1 * s,
    );
    final dst = Rect.fromLTWH(sheet.left + lay.ox * s, sheet.top + lay.oy * s, lay.renderW * s, lay.renderH * s);

    canvas.save();
    canvas.clipRect(clip);
    final img = image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawRect(dst, Paint()..color = Kami.line);
    }
    canvas.restore();

    if (showCutLines) {
      canvas.drawRect(
          clip,
          Paint()
            ..color = Kami.stone
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    }
  }

  @override
  bool shouldRepaint(covariant _SheetPainter old) => true;
}
