import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Перегляд сторінок: превʼю (свайп — сусідня сторінка) і стрічка мініатюр під ним, як у галереї.
/// [pages] — сторінки, які видно (напр. лише вибрані для друку), індекси з нуля.
class PagePager extends StatelessWidget {
  const PagePager({
    super.key,
    required this.preview,
    required this.pages,
    required this.total,
    required this.index,
    required this.onIndexChanged,
    required this.thumbFor,
    this.unit = 'Сторінка',
    this.trailing,
  });

  final Widget preview;
  final List<int> pages;
  final int total;
  final int index;
  final ValueChanged<int> onIndexChanged;
  final Future<ui.Image> Function(int page) thumbFor;
  final String unit; // «Сторінка» / «Аркуш»
  final Widget? trailing; // напр. «Редагувати аркуші»

  void _step(int dir) {
    final i = pages.indexOf(index);
    final next = i < 0 ? 0 : i + dir;
    if (next >= 0 && next < pages.length) onIndexChanged(pages[next]);
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final pos = pages.indexOf(index);
    final label = pages.length == total
        ? '$unit ${index + 1} з $total'
        : '$unit ${index + 1} · ${pos + 1} з ${pages.length} вибраних';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 150) _step(v < 0 ? 1 : -1);
          },
          child: SizedBox(height: 260, child: preview),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 8),
          _PageStrip(pages: pages, current: index, thumbFor: thumbFor, onTap: onIndexChanged),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pages.length > 1) ...[
              IconButton(onPressed: pos > 0 ? () => _step(-1) : null, icon: const Icon(Icons.chevron_left)),
              Text(label, style: small),
              IconButton(
                  onPressed: pos < pages.length - 1 ? () => _step(1) : null, icon: const Icon(Icons.chevron_right)),
            ],
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

class _PageStrip extends StatefulWidget {
  const _PageStrip({required this.pages, required this.current, required this.thumbFor, required this.onTap});

  final List<int> pages;
  final int current;
  final Future<ui.Image> Function(int page) thumbFor;
  final ValueChanged<int> onTap;

  @override
  State<_PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<_PageStrip> {
  static const _w = 50.0, _gap = 8.0;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_PageStrip old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current || old.pages.length != widget.pages.length) _reveal();
  }

  /// Прокручує стрічку так, щоб поточна сторінка була посередині.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final i = widget.pages.indexOf(widget.current);
      if (i < 0) return;
      final target = i * (_w + _gap) - (_scroll.position.viewportDimension - _w) / 2;
      _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: widget.pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final page = widget.pages[i];
          final selected = page == widget.current;
          return GestureDetector(
            onTap: () => widget.onTap(page),
            child: SizedBox(
              width: _w,
              child: Column(
                children: [
                  Container(
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: selected ? Kami.shu : Kami.line, width: selected ? 2 : 1),
                    ),
                    child: FutureBuilder<ui.Image>(
                      future: widget.thumbFor(page),
                      builder: (context, snap) =>
                          snap.hasData ? RawImage(image: snap.data, fit: BoxFit.contain) : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${page + 1}', style: small?.copyWith(color: selected ? Kami.shu : null)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
