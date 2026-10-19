// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import 'loquet_painter.dart';
import 'loquet_pose.dart';

/// A one-off movement asked by the engine.
enum LoquetFx { hop, shake, stretch, wobble, backflip }

/// Loquet: animates between moods by itself (cross-fade, then an entry effect) and, with [life], breathes,
/// blinks and looks around. [still] (performance mode, reduced motion) swaps poses instantly and animates
/// nothing. Never carries information alone: [semanticLabel] says what the face shows.
class Loquet extends StatefulWidget {
  const Loquet({
    super.key,
    required this.mood,
    required this.semanticLabel,
    this.accessory,
    this.size = 96,
    this.eyeX = 0.5,
    this.still = false,
    this.life = false,
    this.fx,
  });

  final LoquetMood mood;
  final String semanticLabel;
  final LoquetAccessory? accessory;
  final double size;
  final double eyeX;
  final bool still;
  final bool life;
  final LoquetFx? fx;

  @override
  State<Loquet> createState() => _LoquetState();
}

class _LoquetState extends State<Loquet> with TickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _effect = AnimationController(vsync: this);
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
  );
  late final _look = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _breath = AnimationController(vsync: this);
  LoquetMood? _previous;
  LoquetFx? _playing;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _syncLife();
  }

  @override
  void didUpdateWidget(Loquet old) {
    super.didUpdateWidget(old);
    if (old.life != widget.life ||
        old.still != widget.still ||
        old.mood != widget.mood) {
      _syncLife();
    }
    if (widget.still) return;
    if (old.mood != widget.mood) {
      _previous = old.mood;
      final entry = switch (widget.mood) {
        LoquetMood.happy => LoquetFx.hop,
        LoquetMood.sad || LoquetMood.alert => LoquetFx.shake,
        LoquetMood.dizzy => LoquetFx.wobble,
        LoquetMood.connecting => null, // bob, below
        _ => old.mood == LoquetMood.sleep ? LoquetFx.stretch : null,
      };
      _fade.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() => _previous = null);
        if (widget.mood == LoquetMood.connecting) {
          _play(null, const Duration(milliseconds: 520));
        } else if (entry != null) {
          _play(entry);
        }
      });
    } else if (widget.fx != null && widget.fx != old.fx) {
      _play(widget.fx);
    }
  }

  void _play(LoquetFx? fx, [Duration? duration]) {
    _playing = fx;
    _effect
      ..duration =
          duration ??
          switch (fx) {
            LoquetFx.wobble ||
            LoquetFx.backflip => const Duration(milliseconds: 600),
            LoquetFx.stretch => const Duration(milliseconds: 420),
            _ => const Duration(milliseconds: 360),
          }
      ..forward(from: 0);
  }

  /// Widget-owned timers, only with [Loquet.life] and never when still.
  void _syncLife() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    if (!widget.life || widget.still) return;
    final mood = widget.mood;
    void every(Duration d, void Function() run) =>
        _timers.add(Timer.periodic(d, (_) => run()));
    if (LoquetPose.of(mood).eyes == LoquetEyes.open ||
        mood == LoquetMood.cheerful) {
      every(const Duration(seconds: 4), () => _blink.forward(from: 0));
    }
    if (mood == LoquetMood.idle || mood == LoquetMood.cheerful) {
      every(const Duration(seconds: 9), () => _look.forward(from: 0));
    }
    final breath = mood == LoquetMood.sleep
        ? const Duration(milliseconds: 4800)
        : const Duration(milliseconds: 3200);
    _breath.duration = breath;
    every(breath, () => _breath.forward(from: 0));
    if (mood == LoquetMood.cheerful) {
      every(const Duration(seconds: 6), () => _play(LoquetFx.hop));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    for (final c in [_fade, _effect, _blink, _look, _breath]) {
      c.dispose();
    }
    super.dispose();
  }

  LoquetPainter _painter(LoquetMood mood, UfColors colors) {
    final p = _effect.value;
    final wave = sin(pi * p);
    var pose = LoquetPose.of(mood, eyeX: widget.eyeX);
    if (_look.isAnimating) {
      // −4 → 4 → 0
      final t = _look.value;
      pose = pose.lookingAt(t < 0.5 ? -4 + 16 * t : 4 - 8 * (t - 0.5));
    }
    return LoquetPainter(
      pose: pose,
      palette: LoquetPalette.of(pose.tone, colors),
      accessory: widget.accessory,
      blink: _blink.isAnimating ? 1 - (2 * _blink.value - 1).abs() : 0,
      squash:
          switch (_playing) {
            LoquetFx.hop when _effect.isAnimating =>
              0.5 * sin(2 * pi * p).clamp(0, 1),
            LoquetFx.stretch when _effect.isAnimating => -wave,
            _ => 0,
          } +
          (_breath.isAnimating ? 0.15 * sin(pi * _breath.value) : 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<UfColors>()!;
    final size = widget.size;
    return SizedBox.square(
      dimension: size,
      child: Semantics(
        label: widget.semanticLabel,
        image: true,
        child: AnimatedBuilder(
          animation: Listenable.merge([_fade, _effect, _blink, _look, _breath]),
          builder: (context, _) {
            final p = _effect.value;
            final moving = _effect.isAnimating;
            final offset = switch (_playing) {
              _ when !moving => Offset.zero,
              LoquetFx.hop => Offset(0, -0.06 * size * sin(pi * p)),
              LoquetFx.shake => Offset(
                0.04 * size * sin(4 * pi * p) * (1 - p),
                0,
              ),
              null => Offset(
                0,
                -0.03 * size * sin(4 * pi * p),
              ), // connecting bob, twice
              _ => Offset.zero,
            };
            final angle = switch (_playing) {
              _ when !moving => 0.0,
              LoquetFx.wobble => 8 * pi / 180 * sin(4 * pi * p) * (1 - p),
              LoquetFx.backflip => 2 * pi * p,
              _ => 0.0,
            };
            final fading = _previous != null && _fade.isAnimating;
            final t = UfMotion.curve.transform(_fade.value);
            Widget paint(LoquetMood mood) => CustomPaint(
              size: Size.square(size),
              painter: _painter(mood, colors),
            );
            return Transform.translate(
              offset: offset,
              child: Transform.rotate(
                angle: angle,
                child: fading
                    ? Stack(
                        children: [
                          Opacity(opacity: 1 - t, child: paint(_previous!)),
                          Opacity(opacity: t, child: paint(widget.mood)),
                        ],
                      )
                    : paint(widget.mood),
              ),
            );
          },
        ),
      ),
    );
  }
}
