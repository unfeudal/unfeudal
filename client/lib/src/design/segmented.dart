// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';
import 'tokens.dart';

/// A segmented control: a `neutral` track whose `panel` pill slides to the picked segment, whatever their count.
/// Null [onChanged] disables it. [expand] shares the full width equally; otherwise each segment fits its label.
class UfSegmented<T> extends StatefulWidget {
  const UfSegmented({
    super.key,
    required this.segments,
    required this.selected,
    this.onChanged,
    this.expand = false,
  });

  final List<(T, Widget)> segments;
  final T selected;
  final ValueChanged<T>? onChanged;
  final bool expand;

  @override
  State<UfSegmented<T>> createState() => _UfSegmentedState<T>();
}

class _UfSegmentedState<T> extends State<UfSegmented<T>>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(vsync: this, value: 1);
  late final _curve = CurvedAnimation(parent: _slide, curve: UfMotion.enter);
  late int _from = _index, _to = _index;

  int get _index => widget.segments.indexWhere((s) => s.$1 == widget.selected);

  @override
  void didUpdateWidget(UfSegmented<T> old) {
    super.didUpdateWidget(old);
    if (_index == _to) return;
    _from = _to;
    _to = _index;
    _slide
      ..duration = UfMotion.of(context).base
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final pick = widget.onChanged;
    return Opacity(
      opacity: pick == null ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.neutral,
          borderRadius: UfRadius.card,
        ),
        child: _Track(
          slide: _curve,
          from: _from,
          to: _to,
          expand: widget.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: UfRadius.control,
                border: Border.all(color: colors.line),
              ),
            ),
            for (final (i, (value, label)) in widget.segments.indexed)
              _Segment(
                selected: i == _to,
                onTap: pick == null ? null : () => pick(value),
                child: label,
              ),
          ],
        ),
      ),
    );
  }
}

/// 28 px, 12 px sides, 12/600: `muted` at rest, `text` when picked or hovered, a 2 px ring on keyboard focus.
class _Segment extends StatefulWidget {
  const _Segment({required this.selected, this.onTap, required this.child});

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hover = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final onTap = widget.onTap;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: FocusableActionDetector(
        enabled: onTap != null,
        mouseCursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => onTap?.call(),
          ),
        },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: UfHeight.small,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: UfRadius.control,
              boxShadow: _focus
                  ? [BoxShadow(color: colors.focus, spreadRadius: 2)]
                  : null,
            ),
            child: AnimatedDefaultTextStyle(
              duration: UfMotion.of(context).fast,
              curve: UfMotion.standard,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.selected || _hover ? colors.text : colors.muted,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the segments in a row 2 px apart, then the pill (first child) between the rects of [from] and [to].
class _Track extends MultiChildRenderObjectWidget {
  const _Track({
    required this.slide,
    required this.from,
    required this.to,
    required this.expand,
    required super.children,
  });

  final Animation<double> slide;
  final int from, to;
  final bool expand;

  @override
  _RenderTrack createRenderObject(BuildContext context) =>
      _RenderTrack(slide, from, to, expand);

  @override
  void updateRenderObject(BuildContext context, _RenderTrack track) => track
    ..slide = slide
    ..from = from
    ..to = to
    ..expand = expand;
}

class _TrackSlot extends ContainerBoxParentData<RenderBox> {}

class _RenderTrack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TrackSlot>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TrackSlot> {
  _RenderTrack(this._slide, this._from, this._to, this._expand);

  static const _gap = 2.0;

  Animation<double> _slide;
  set slide(Animation<double> value) {
    if (value == _slide) return;
    if (attached) {
      _slide.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _slide = value;
    markNeedsLayout();
  }

  int _from, _to;
  set from(int value) {
    if (value == _from) return;
    _from = value;
    markNeedsLayout();
  }

  set to(int value) {
    if (value == _to) return;
    _to = value;
    markNeedsLayout();
  }

  bool _expand;
  set expand(bool value) {
    if (value == _expand) return;
    _expand = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TrackSlot) child.parentData = _TrackSlot();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _slide.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _slide.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    final pill = firstChild!;
    final segments = getChildrenAsList().skip(1).toList();
    final share = _expand && constraints.hasBoundedWidth && segments.isNotEmpty
        ? (constraints.maxWidth - _gap * (segments.length - 1)) /
              segments.length
        : null;
    final rects = <Rect>[];
    var x = 0.0, height = 0.0;
    for (final segment in segments) {
      segment.layout(
        share == null
            ? const BoxConstraints()
            : BoxConstraints.tightFor(width: share),
        parentUsesSize: true,
      );
      (segment.parentData! as _TrackSlot).offset = Offset(x, 0);
      rects.add(Offset(x, 0) & segment.size);
      x += segment.size.width + _gap;
      if (segment.size.height > height) height = segment.size.height;
    }
    size = constraints.constrain(Size(segments.isEmpty ? 0 : x - _gap, height));
    if (rects.isEmpty || _to < 0) {
      pill.layout(BoxConstraints.tight(Size.zero));
      return;
    }
    final from = rects[_from < 0 ? _to : _from.clamp(0, rects.length - 1)];
    final at = Rect.lerp(
      from,
      rects[_to.clamp(0, rects.length - 1)],
      _slide.value,
    )!;
    pill.layout(BoxConstraints.tight(at.size));
    (pill.parentData! as _TrackSlot).offset = at.topLeft;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
