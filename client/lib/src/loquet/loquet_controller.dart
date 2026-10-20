// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/settings.dart';
import 'line_bank.dart';
import 'loquet.dart';
import 'loquet_pose.dart';
import 'mood.dart';
import 'reaction_engine.dart';

/// What every Loquet spot shows: the current reaction while it holds, else the engine's baseline. Timers
/// run only while a spot is attached, so widget tests settle with no pending timer.
class LoquetController extends ChangeNotifier {
  LoquetController(this.engine);

  final ReactionEngine engine;

  /// Idle life (breathing, blinking) in the spots; `main()` turns it on.
  bool life = false;

  Reaction? _current;
  bool _bubble = false;
  double _eyeX = 0.5;
  final _queue = <Reaction>[];
  int _attached = 0;
  Timer? _bubbleTimer, _holdTimer, _tickTimer;

  LoquetMood get mood => _current?.mood ?? engine.baseline;

  /// Never on a serious face.
  LoquetAccessory? get accessory =>
      mood.serious ? null : _current?.accessory ?? engine.sessionAccessory;

  /// The reaction showing now; spots pick its text once.
  Reaction? get current => _current;

  LineKey? get line => _bubble ? _current?.line : null;
  Map<String, String> get params => _current?.params ?? const {};
  bool get reasons => _current?.reasons ?? false;
  LoquetFx? get fx => _current?.fx;
  double get eyeX => _eyeX;
  bool get visible => mode != LoquetMode.off;

  LoquetMode get mode => engine.mode;

  set mode(LoquetMode value) {
    engine.mode = value;
    if (value != LoquetMode.on) _bubble = false;
    notifyListeners();
  }

  /// A grave reaction replaces the current one; a lesser one waits behind a grave one (3 at most).
  void show(Reaction? r) {
    if (r == null) return;
    final current = _current;
    if (current != null && current.grave && !r.grave) {
      _queue.add(r);
      if (_queue.length > 3) _queue.removeAt(0);
      return;
    }
    _play(r);
  }

  /// Eyes on the caret for a moment.
  void watch(double eyeX) {
    show(
      const Reaction(LoquetMood.watching, hold: Duration(milliseconds: 1500)),
    );
    if (_current?.mood == LoquetMood.watching) {
      _eyeX = eyeX;
      notifyListeners();
    }
  }

  void setHealth(VaultHealth health) {
    final before = engine.baseline;
    engine.health = health;
    if (engine.baseline != before) notifyListeners();
  }

  void attach() {
    if (_attached++ > 0) return;
    _armReaction();
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      show(engine.tick());
      notifyListeners();
    });
  }

  void detach() {
    if (_attached == 0 || --_attached > 0) return;
    _cancel();
  }

  void _play(Reaction r) {
    _current = r;
    _bubble = r.line != null;
    _eyeX = 0.5;
    _bubbleTimer?.cancel();
    _holdTimer?.cancel();
    if (_attached > 0) _armReaction();
    notifyListeners();
  }

  // The current reaction's bubble and hold, in full.
  void _armReaction() {
    final r = _current;
    if (r == null) return;
    if (_bubble) {
      _bubbleTimer = Timer(r.bubble, () {
        _bubble = false;
        notifyListeners();
      });
    }
    _holdTimer = Timer(r.duration, _end);
  }

  void _end() {
    _bubbleTimer?.cancel();
    _current = null;
    _bubble = false;
    _eyeX = 0.5;
    if (_queue.isNotEmpty) {
      _play(_queue.removeAt(0));
    } else {
      notifyListeners();
    }
  }

  void _cancel() {
    for (final t in [_bubbleTimer, _holdTimer, _tickTimer]) {
      t?.cancel();
    }
    _bubbleTimer = _holdTimer = _tickTimer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}
