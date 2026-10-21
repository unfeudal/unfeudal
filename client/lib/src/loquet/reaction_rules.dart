// SPDX-License-Identifier: Apache-2.0
part of 'reaction_engine.dart';

extension on ReactionEngine {
  Reaction? _unlocked(String? displayName) {
    final first = memory.firstUnlock;
    if (first == null) {
      memory.firstUnlock = _now();
      unawaited(memory.save());
    }
    if (first != null &&
        _now().difference(first) >= const Duration(days: 365)) {
      final r = _gate(
        const Reaction(
          LoquetMood.happy,
          line: LineKey.oneYear,
          important: true,
        ),
        once: 'oneYear',
      );
      if (r != null) return r;
    }
    final hour = _now().hour;
    if (hour >= 5 && hour < 8) {
      final r = _gate(
        const Reaction(LoquetMood.yawn, line: LineKey.earlyYawn),
        once: 'yawn:$_day',
      );
      if (r != null) return r;
    }
    return _gate(
      Reaction(
        LoquetMood.happy,
        line: LineKey.welcome,
        params: {'name': ?displayName},
      ),
    );
  }

  Reaction? _connected(ConnectSucceeded event) {
    memory.connections++;
    unawaited(memory.save());
    for (final (count, line, onceKey) in [
      (100, LineKey.connections100, 'connections100'),
      (1000, LineKey.connections1000, 'connections1000'),
    ]) {
      if (memory.connections == count) {
        final r = _gate(
          Reaction(LoquetMood.happy, line: line, important: true),
          once: onceKey,
        );
        if (r != null) return r;
      }
    }
    if (event.user == 'root' && !_rootHosts.contains(event.hostId)) {
      final r = _gate(
        const Reaction(
          LoquetMood.happy,
          accessory: LoquetAccessory.hardHat,
          line: LineKey.root,
        ),
        egg: true,
      );
      if (r != null) {
        _rootHosts.add(event.hostId);
        return r;
      }
    }
    final t = _now();
    if (t.weekday == DateTime.friday &&
        t.hour >= 17 &&
        event.tags.contains('prod')) {
      final r = _gate(
        const Reaction(LoquetMood.happy, line: LineKey.fridayProd),
        once: 'friday:$_day',
      );
      if (r != null) return r;
    }
    return _gate(const Reaction(LoquetMood.happy, line: LineKey.connected));
  }

  Reaction? _hostCreated(String name) {
    memory.hostsCreated++;
    unawaited(memory.save());
    if (name == 'localhost') {
      final r = _gate(
        const Reaction(LoquetMood.happy, line: LineKey.localhost),
        once: 'localhost',
        egg: true,
      );
      if (r != null) return r;
    }
    if (memory.hostsCreated == 1) {
      final r = _gate(
        const Reaction(
          LoquetMood.happy,
          line: LineKey.firstHost,
          important: true,
        ),
        once: 'firstHost',
      );
      if (r != null) return r;
    }
    if (memory.hostsCreated == 42) {
      final r = _gate(
        const Reaction(LoquetMood.happy, line: LineKey.host42),
        once: 'host42',
        egg: true,
      );
      if (r != null) return r;
    }
    return _gate(const Reaction(LoquetMood.happy));
  }

  Reaction? _clicked() {
    final t = _now();
    _clicks
      ..add(t)
      ..removeWhere((c) => t.difference(c) > const Duration(seconds: 4));
    if (_clicks.length >= 10) {
      _clicks.clear();
      final r = _gate(
        const Reaction(LoquetMood.dizzy, line: LineKey.dizzy),
        once: 'dizzy:$_day',
        egg: true,
      );
      if (r != null) return r;
    }
    if (baseline == LoquetMood.concerned) {
      return _gate(
        const Reaction(
          LoquetMood.concerned,
          showsReasons: true,
          hold: Duration(seconds: 6),
        ),
      );
    }
    return _gate(Reaction(baseline, line: LineKey.idleClick));
  }
}
