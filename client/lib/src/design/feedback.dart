// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'banner.dart';
import 'motion.dart';
import 'tokens.dart';

/// Pulses its subtree's opacity from 1 to .5 and back every 1.6 s while content loads; static when motion is still.
class UfSkeleton extends StatefulWidget {
  const UfSkeleton({super.key, required this.child});

  final Widget child;

  @override
  State<UfSkeleton> createState() => _UfSkeletonState();
}

class _UfSkeletonState extends State<UfSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (UfMotion.of(context) == UfMotion.still) {
      _pulse.reset();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final there = 1 - (2 * _pulse.value - 1).abs();
        return Opacity(
          opacity: 1 - 0.5 * Curves.easeInOut.transform(there),
          child: child,
        );
      },
      child: widget.child,
    ),
  );
}

/// One `neutral` placeholder block, radius 4; [circle] makes it round. Without [width] it fills its parent.
class UfSkeletonBlock extends StatelessWidget {
  const UfSkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.circle = false,
  });

  final double? width;
  final double height;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: UfColors.of(context).neutral,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : UfRadius.key,
    ),
  );
}

/// The tree while it loads: a title bar 44 % wide, then rows indented 14 with a dot and a bar.
class UfTreeSkeleton extends StatelessWidget {
  const UfTreeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => UfSkeleton(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        const FractionallySizedBox(
          widthFactor: 0.44,
          child: UfSkeletonBlock(height: 12),
        ),
        for (final width in const [0.58, 0.40, 0.66])
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Row(
              spacing: 8,
              children: [
                const UfSkeletonBlock(width: 14, height: 14, circle: true),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: width,
                    child: const UfSkeletonBlock(height: 10),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A notice inside a dialog or a panel: a `warnSoft` or `dangerSoft` box, the tone's icon and the 13.5 message.
/// [UfNotice.row] lays it on one line with small [actions] on the right, at the top of a section.
class UfNotice extends StatelessWidget {
  const UfNotice({super.key, required this.tone, required this.message})
    : _row = false,
      actions = const [];

  const UfNotice.row({
    super.key,
    required this.tone,
    required this.message,
    this.actions = const [],
  }) : _row = true;

  final BannerTone tone;
  final String message;

  /// Small buttons ([smallButton]).
  final List<Widget> actions;
  final bool _row;

  @override
  Widget build(BuildContext context) {
    final (color, fill, icon) = tone.style(UfColors.of(context));
    final text = Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13.5),
    );
    return Container(
      padding: _row
          ? const EdgeInsets.fromLTRB(12, 8, 8, 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: _row ? UfRadius.control : UfRadius.card,
      ),
      child: _row
          ? Row(
              spacing: 12,
              children: [
                Icon(icon, size: 16, color: color),
                Expanded(child: text),
                ...actions,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 16, color: color),
                ),
                Expanded(child: text),
              ],
            ),
    );
  }
}

enum UfChipTone { ok, warn, danger, muted }

/// A state written on a soft fill, 12/600 without an edge: `okSoft`, `warnSoft`, `dangerSoft`, or bare `muted`.
class UfStatusChip extends StatelessWidget {
  const UfStatusChip(this.label, {super.key, required this.tone});

  final String label;
  final UfChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final (fill, ink) = switch (tone) {
      UfChipTone.ok => (colors.okSoft, colors.ok),
      UfChipTone.warn => (colors.warnSoft, colors.warn),
      UfChipTone.danger => (colors.dangerSoft, colors.danger),
      UfChipTone.muted => (Colors.transparent, colors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: fill, borderRadius: UfRadius.key),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: ink,
          fontWeight: tone == UfChipTone.muted
              ? FontWeight.w400
              : FontWeight.w600,
        ),
      ),
    );
  }
}

/// Shakes its child sideways once (0, -8, 8, -5, 5, 0 px over 360 ms) each time [shakes] grows, after a
/// wrong password or a refused form; not at all when motion is still.
class UfShake extends StatefulWidget {
  const UfShake({super.key, required this.shakes, required this.child});

  /// A counter the caller bumps to shake again.
  final int shakes;
  final Widget child;

  @override
  State<UfShake> createState() => _UfShakeState();
}

class _UfShakeState extends State<UfShake> with SingleTickerProviderStateMixin {
  static final _offsets = TweenSequence([
    for (final (from, to) in const [(0, -8), (-8, 8), (8, -5), (-5, 5), (5, 0)])
      TweenSequenceItem(
        tween: Tween(begin: from.toDouble(), end: to.toDouble()),
        weight: 1,
      ),
  ]);

  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void didUpdateWidget(UfShake old) {
    super.didUpdateWidget(old);
    if (widget.shakes > old.shakes && UfMotion.of(context) != UfMotion.still) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shake,
    builder: (context, child) => Transform.translate(
      offset: Offset(_offsets.evaluate(_shake), 0),
      child: child,
    ),
    child: widget.child,
  );
}

/// Plays once when first shown: each [UfStaggerItem] below fades in and rises 4 px over 200 ms, 20 ms after the
/// previous one, for the first 8; rows shown later appear at once. Nothing moves when motion is still.
class UfStagger extends StatefulWidget {
  const UfStagger({super.key, required this.child});

  final Widget child;

  @override
  State<UfStagger> createState() => _UfStaggerState();
}

class _UfStaggerState extends State<UfStagger>
    with SingleTickerProviderStateMixin {
  static const _rows = 8, _gapMs = 20, _rowMs = 200;
  static const _totalMs = _rowMs + (_rows - 1) * _gapMs;

  late final _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_play.isAnimating || _play.isCompleted) return;
    if (UfMotion.of(context) == UfMotion.still) {
      _play.value = 1;
    } else {
      _play.forward();
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _StaggerScope(play: _play, child: widget.child);
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({required this.play, required super.child});

  final Animation<double> play;

  @override
  bool updateShouldNotify(_StaggerScope old) => play != old.play;
}

/// The row at [index] of a [UfStagger]; outside one, or past the eighth row, it shows its child as is.
class UfStaggerItem extends StatelessWidget {
  const UfStaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final play = context
        .dependOnInheritedWidgetOfExactType<_StaggerScope>()
        ?.play;
    if (play == null || index >= _UfStaggerState._rows) {
      return child;
    }
    const total = _UfStaggerState._totalMs;
    final start = index * _UfStaggerState._gapMs;
    final appear = Interval(
      start / total,
      math.min(1, (start + _UfStaggerState._rowMs) / total),
      curve: UfMotion.enter,
    );
    return AnimatedBuilder(
      animation: play,
      builder: (context, child) {
        final t = appear.transform(play.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
