// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'motion.dart';
import 'tokens.dart';

enum SealState { connected, verify, changed, offline, connecting }

/// Host status: each state differs by shape, not by colour alone.
class Seal extends StatefulWidget {
  const Seal({super.key, required this.state, this.size = 14});

  final SealState state;
  final double size;

  @override
  State<Seal> createState() => _SealState();
}

class _SealState extends State<Seal> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(Seal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  void _syncSpin() {
    final spins =
        widget.state == SealState.connecting &&
        UfMotion.of(context) != UfMotion.still;
    if (spins && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spins && _spin.isAnimating) {
      _spin.reset();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = switch (widget.state) {
      SealState.connected => l.sealConnected,
      SealState.verify => l.sealVerify,
      SealState.changed => l.sealChanged,
      SealState.offline => l.sealOffline,
      SealState.connecting => l.sealConnecting,
    };
    return Semantics(
      container: true,
      label: label,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _SealPainter(widget.state, UfColors.of(context), _spin),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  _SealPainter(this.state, this.colors, this.spin) : super(repaint: spin);

  final SealState state;
  final UfColors colors;
  final Animation<double> spin;

  // geometry of the design's 16-unit seal
  static const _center = Offset(8, 8);
  static const _ring = 6.5;
  static const _dot = 3.6;
  static const _dashes = 12;
  static const _dashLength = 2.0;
  static const _spinLength = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    final ringColor = switch (state) {
      SealState.connected => colors.ok,
      SealState.verify => colors.warn,
      SealState.changed => colors.danger,
      SealState.connecting => colors.warn,
      SealState.offline => colors.muted,
    };
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final ringRect = Rect.fromCircle(center: _center, radius: _ring);
    stroke.color = ringColor;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(
        ringRect,
        i * 2 * math.pi / _dashes,
        _dashLength / _ring,
        false,
        stroke,
      );
    }
    switch (state) {
      case SealState.connected:
        canvas.drawCircle(_center, _dot, Paint()..color = colors.ok);
      case SealState.verify:
        final dot = Rect.fromCircle(center: _center, radius: _dot);
        canvas.drawArc(
          dot,
          -math.pi / 2,
          math.pi,
          true,
          Paint()..color = colors.warn,
        );
      case SealState.changed:
        canvas.drawCircle(_center, _ring, Paint()..color = colors.danger);
        stroke.color = colors.onDanger;
        canvas.drawLine(
          const Offset(5.6, 5.6),
          const Offset(10.4, 10.4),
          stroke,
        );
        canvas.drawLine(
          const Offset(10.4, 5.6),
          const Offset(5.6, 10.4),
          stroke,
        );
      case SealState.offline:
        break;
      case SealState.connecting:
        stroke.color = colors.text;
        canvas.drawArc(
          ringRect,
          spin.value * 2 * math.pi,
          _spinLength / _ring,
          false,
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.state != state || old.colors != colors;
}
