// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';

import '../events/app_events.dart';
import '../settings/settings.dart';
import '../version.dart';
import 'line_bank.dart';
import 'loquet.dart';
import 'loquet_memory.dart';
import 'loquet_pose.dart';
import 'mood.dart';

part 'reaction_rules.dart';

/// What Loquet does for a moment: a mood over the baseline, maybe an accessory, a line or a movement.
class Reaction {
  const Reaction(
    this.mood, {
    this.accessory,
    this.line,
    this.params = const {},
    this.important = false,
    this.spontaneous = false,
    this.showsReasons = false,
    this.hold,
    this.fx,
  });

  final LoquetMood mood;
  final LoquetAccessory? accessory;
  final LineKey? line;
  final Map<String, String> params;
  final bool important;

  /// Not the answer to a user action: subject to the 10-minute cooldown.
  final bool spontaneous;

  /// Show the mood reasons in the status card.
  final bool showsReasons;
  final Duration? hold;
  final LoquetFx? fx;

  Duration get bubble =>
      important ? const Duration(seconds: 6) : const Duration(seconds: 3);
  Duration get duration => hold ?? bubble;

  /// Holds against lesser reactions.
  bool get grave => important || mood.isSerious;
}

/// Turns app events, clock ticks, clicks and keys into reactions. No widgets or timers: the clock is injected;
/// local counters and once-keys live in [memory].
class ReactionEngine {
  ReactionEngine({
    required this.memory,
    required this._now,
    this._projectRelease = firstPublicRelease,
  });

  final LoquetMemory memory;
  final DateTime Function() _now;

  // `yyyy-mm-dd` of the first public release: a party hat on its anniversaries.
  final String? _projectRelease;
  LoquetMode mode = LoquetMode.on;
  VaultHealth health = VaultHealth.none;
  bool _offline = false;
  bool _dozing = false;
  DateTime? _lastInput;
  DateTime? _lastSpontaneous;
  final _rootHosts = <String>{};
  final _clicks = <DateTime>[];
  var _konami = 0;

  static const _konamiCode = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyA,
  ];

  String get _day => LoquetMemory.day(_now());

  /// Terminal input less than 3 s ago.
  bool get isTyping =>
      _lastInput != null &&
      _now().difference(_lastInput!) < const Duration(seconds: 3);

  void noteTerminalInput() => _lastInput = _now();

  /// The resting mood: offline, then dozing, then concerned, then night, then the vault's mood.
  LoquetMood get baseline {
    final mood = health.mood;
    if (_offline) return LoquetMood.offline;
    if (_dozing) return LoquetMood.sleep;
    if (mood == LoquetMood.concerned) return mood;
    if (_now().hour < 5) return LoquetMood.sleepy;
    return mood;
  }

  LoquetAccessory? get sessionAccessory {
    if (mode != LoquetMode.on) return null;
    if (_rootHosts.isNotEmpty) return LoquetAccessory.hardHat;
    final t = _now();
    if (t.month == 12 && t.day >= 24 && t.day <= 26) {
      return LoquetAccessory.woollyHat;
    }
    if (t.month == 4 && t.day == 1) return LoquetAccessory.fakeNose;
    // Loquet day (the first unlock) and the project's anniversary, from the next year on
    bool anniversary(DateTime? d) =>
        d != null && d.month == t.month && d.day == t.day && t.year > d.year;
    final release = _projectRelease;
    if (anniversary(memory.firstUnlock?.toLocal()) ||
        anniversary(
          release == null || release.isEmpty
              ? null
              : DateTime.tryParse(release),
        )) {
      return LoquetAccessory.partyHat;
    }
    return null;
  }

  /// Root sessions without an open tab no longer wear the hard hat.
  void tabsChanged(Set<String> openHostIds) =>
      _rootHosts.retainAll(openHostIds);

  Reaction? handle(AppEvent event) {
    switch (event) {
      case Unlocked(:final displayName):
        return _unlocked(displayName);
      case UnlockFailed(:final consecutive) when consecutive >= 3:
        return _gate(
          const Reaction(
            LoquetMood.covering,
            hold: Duration(milliseconds: 1500),
          ),
          once: 'hide:$_day',
          egg: true,
        );
      case ConnectStarted():
        return _gate(
          const Reaction(LoquetMood.connecting, hold: Duration(seconds: 60)),
        );
      case ConnectSucceeded():
        return _connected(event);
      case ConnectFailed():
        return _gate(
          Reaction(baseline, hold: const Duration(milliseconds: 500)),
        );
      case HostKeyChanged():
        return _gate(
          const Reaction(
            LoquetMood.alert,
            line: LineKey.keyChanged,
            important: true,
          ),
        );
      case WentOffline():
        _offline = true;
        return _gate(
          const Reaction(
            LoquetMood.offline,
            line: LineKey.offline,
            spontaneous: true,
          ),
        );
      case CameOnline():
        _offline = false;
        return _gate(
          Reaction(baseline, hold: const Duration(milliseconds: 500)),
        );
      case VaultLocked():
        _rootHosts.clear();
        _dozing = false;
        return _gate(const Reaction(LoquetMood.idle, line: LineKey.lock));
      case UserIdle():
        _dozing = true;
        return _gate(const Reaction(LoquetMood.sleep, spontaneous: true));
      default:
        return _handleUserAction(event);
    }
  }

  Reaction? _handleUserAction(AppEvent event) {
    switch (event) {
      case ThemeChanged(mode: ThemeMode.dark):
        return _gate(
          Reaction(
            baseline,
            accessory: LoquetAccessory.sunglasses,
            hold: const Duration(seconds: 2),
          ),
          once: 'sunglasses:$_day',
          egg: true,
        );
      case HostCreated(:final name):
        return _hostCreated(name);
      case DeviceAdded(:final activeDevices) when activeDevices >= 2:
        return _gate(
          const Reaction(
            LoquetMood.happy,
            line: LineKey.secondDevice,
            important: true,
          ),
          once: 'secondDevice',
        );
      case LoquetClicked():
        return _clicked();
      case SharedVaultCreated():
        return _milestone('sharedVault', LineKey.sharedVault);
      case KeyRotated():
        return _milestone('firstKeyRotation', LineKey.firstKeyRotation);
      default:
        return null;
    }
  }

  /// Each minute.
  Reaction? tick() {
    if (_now().hour < 5) {
      return _gate(
        const Reaction(
          LoquetMood.sleepy,
          line: LineKey.night,
          spontaneous: true,
        ),
        once: 'night:$_day',
        clock: true,
      );
    }
    return null;
  }

  /// Konami (up up down down left right left right B A) completed: a backflip, once a day; a wrong key restarts the sequence.
  Reaction? keyPressed(LogicalKeyboardKey key) {
    if (key == _konamiCode[_konami]) {
      _konami++;
    } else {
      _konami = key == _konamiCode.first ? 1 : 0;
    }
    if (_konami < _konamiCode.length) return null;
    _konami = 0;
    return _gate(
      const Reaction(LoquetMood.happy, fx: LoquetFx.backflip),
      once: 'konami:$_day',
      egg: true,
    );
  }

  // A milestone reached elsewhere in the app, once ever.
  Reaction? _milestone(String onceKey, LineKey line) => _gate(
    Reaction(LoquetMood.happy, line: line, important: true),
    once: onceKey,
  );

  /// First activity after dozing; the widget stretches on leaving `sleep`.
  Reaction? wake() {
    if (!_dozing) return null;
    _dozing = false;
    return _gate(Reaction(baseline));
  }

  // once: memory key consumed when the reaction is shown. egg: easter egg (mode `on` only).
  // clock: a clock rule; when its bubble is gated it returns null and is retried at the next tick.
  Reaction? _gate(
    Reaction r, {
    String? once,
    bool egg = false,
    bool clock = false,
  }) {
    if (mode == LoquetMode.off) return null;
    if (egg && mode != LoquetMode.on) return null;
    if (once != null && memory.hasFired(once)) return null;
    var line = mode == LoquetMode.sober ? null : r.line;
    if (line != null) {
      final last = _lastSpontaneous;
      final cooling =
          r.spontaneous &&
          last != null &&
          _now().difference(last) < const Duration(minutes: 10);
      if (isTyping || cooling) {
        // Never a bubble while the terminal is typed in; cooldown only for spontaneous ones. A clock rule
        // returns null so nothing is consumed and the next tick retries; otherwise the mood still shows.
        if (clock) return null;
        line = null;
      } else if (r.spontaneous) {
        _lastSpontaneous = _now();
      }
    }
    if (once != null) {
      memory.fire(once);
      unawaited(memory.save());
    }
    return Reaction(
      r.mood,
      accessory: r.accessory,
      line: line,
      params: r.params,
      important: r.important,
      spontaneous: r.spontaneous,
      showsReasons: r.showsReasons,
      hold: r.hold,
      fx: r.fx,
    );
  }
}
