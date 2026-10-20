// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/loquet.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/loquet/mood.dart';
import 'package:unfeudal_client/src/loquet/reaction_engine.dart';

ConnectSucceeded connect({
  String user = 'deploy',
  List<String> tags = const [],
  String hostId = 'h',
}) => ConnectSucceeded(hostId: hostId, user: user, tags: tags);

void main() {
  late DateTime now;
  late LoquetMemory memory;
  late ReactionEngine e;
  setUp(() {
    now = DateTime(2026, 10, 15, 12);
    memory = LoquetMemory();
    e = ReactionEngine(memory: memory, now: () => now);
  });

  test('early first unlock yawns once per day, then welcomes by name', () {
    now = DateTime(2026, 10, 15, 6, 30);
    final first = e.handle(const Unlocked(displayName: 'Camille'))!;
    expect((first.mood, first.line), (LoquetMood.yawn, LineKey.earlyYawn));
    final second = e.handle(const Unlocked(displayName: 'Camille'))!;
    expect(second.mood, LoquetMood.happy);
    expect(second.line, LineKey.welcome);
    expect(second.params, {'name': 'Camille'});
    expect(memory.firstUnlock, isNotNull);
  });

  test('Friday 17:30 on a prod host: once per evening', () {
    now = DateTime(2026, 10, 16, 17, 30);
    expect(e.handle(connect(tags: ['prod']))!.line, LineKey.fridayProd);
    expect(e.handle(connect(tags: ['prod']))!.line, LineKey.connected);
  });

  test('not Friday, or before 17:00, or no prod tag: plain connected', () {
    now = DateTime(2026, 10, 15, 17, 30);
    expect(e.handle(connect(tags: ['prod']))!.line, LineKey.connected);
    now = DateTime(2026, 10, 16, 16, 59);
    expect(e.handle(connect(tags: ['prod']))!.line, LineKey.connected);
    now = DateTime(2026, 10, 16, 18);
    expect(e.handle(connect(tags: ['staging']))!.line, LineKey.connected);
  });

  test('root wears a hard hat for the session', () {
    final r = e.handle(connect(user: 'root'))!;
    expect((r.accessory, r.line), (LoquetAccessory.hardHat, LineKey.root));
    expect(e.sessionAccessory, LoquetAccessory.hardHat);
    // Same session.
    expect(e.handle(connect(user: 'root'))!.line, LineKey.connected);
    e.tabsChanged({});
    expect(e.sessionAccessory, isNull);
    e.handle(connect(user: 'root'));
    e.handle(const VaultLocked());
    expect(e.sessionAccessory, isNull);
  });

  test('connection milestones fire once ever', () {
    memory.connections = 99;
    final r = e.handle(connect())!;
    expect((r.line, r.important), (LineKey.connections100, true));
    memory.connections = 99;
    expect(e.handle(connect())!.line, LineKey.connected);
    memory.connections = 999;
    expect(e.handle(connect())!.line, LineKey.connections1000);
  });

  test('hosts: first, localhost, 42nd', () {
    expect(e.handle(const HostCreated(name: 'web'))!.line, LineKey.firstHost);
    expect(
      e.handle(const HostCreated(name: 'localhost'))!.line,
      LineKey.localhost,
    );
    expect(e.handle(const HostCreated(name: 'localhost'))!.line, isNull);
    memory.hostsCreated = 41;
    expect(e.handle(const HostCreated(name: 'db'))!.line, LineKey.host42);
    expect(memory.hostsCreated, 42);
  });

  test('second device once', () {
    expect(e.handle(const DeviceAdded(activeDevices: 1)), isNull);
    expect(
      e.handle(const DeviceAdded(activeDevices: 2))!.line,
      LineKey.secondDevice,
    );
    expect(e.handle(const DeviceAdded(activeDevices: 3)), isNull);
  });

  test('one year with Unfeudal, and the party hat on Loquet day', () {
    memory.firstUnlock = DateTime(2025, 10, 15, 9);
    final r = e.handle(const Unlocked())!;
    expect((r.line, r.important), (LineKey.oneYear, true));
    expect(e.sessionAccessory, LoquetAccessory.partyHat);
    now = DateTime(2026, 10, 16, 12);
    expect(e.sessionAccessory, isNull);
  });

  test('party hat on the project anniversary, never on the release day itself nor while the release is unset', () {
    final p = ReactionEngine(
      memory: LoquetMemory(),
      now: () => now,
      projectRelease: '2026-03-07',
    );
    now = DateTime(2026, 3, 7, 12);
    expect(p.sessionAccessory, isNull);
    now = DateTime(2027, 3, 7, 12);
    expect(p.sessionAccessory, LoquetAccessory.partyHat);
    for (final unset in [null, '']) {
      final u = ReactionEngine(
        memory: LoquetMemory(),
        now: () => now,
        projectRelease: unset,
      );
      expect(u.sessionAccessory, isNull, reason: '$unset');
    }
  });

  test('calendar accessories; root wins', () {
    now = DateTime(2026, 12, 24, 10);
    expect(e.sessionAccessory, LoquetAccessory.woollyHat);
    now = DateTime(2027, 4, 1, 10);
    expect(e.sessionAccessory, LoquetAccessory.fakeNose);
    e.handle(connect(user: 'root'));
    expect(e.sessionAccessory, LoquetAccessory.hardHat);
  });

  test('dark theme: sunglasses for two seconds, once a day', () {
    final r = e.handle(const ThemeChanged(mode: ThemeMode.dark))!;
    expect(
      (r.accessory, r.duration),
      (LoquetAccessory.sunglasses, const Duration(seconds: 2)),
    );
    expect(e.handle(const ThemeChanged(mode: ThemeMode.dark)), isNull);
    expect(e.handle(const ThemeChanged(mode: ThemeMode.light)), isNull);
  });

  test('three wrong passwords: hides his face, once a day', () {
    expect(e.handle(const UnlockFailed(consecutive: 2)), isNull);
    final r = e.handle(const UnlockFailed(consecutive: 3))!;
    expect((r.mood, r.line), (LoquetMood.covering, null));
    expect(e.handle(const UnlockFailed(consecutive: 4)), isNull);
  });

  test(
    'clicks: a line, ten quick ones make him dizzy, concerned shows reasons',
    () {
      expect(e.handle(const LoquetClicked())!.line, LineKey.idleClick);
      Reaction? r;
      for (var i = 0; i < 9; i++) {
        now = now.add(const Duration(milliseconds: 300));
        r = e.handle(const LoquetClicked());
      }
      expect((r!.mood, r.line), (LoquetMood.dizzy, LineKey.dizzy));
      e.health = const VaultHealth(conflicts: 1);
      now = now.add(const Duration(seconds: 10));
      final c = e.handle(const LoquetClicked())!;
      expect((c.mood, c.reasons, c.line), (LoquetMood.concerned, true, null));
    },
  );

  test('Konami in the app: backflip once a day; a wrong key restarts', () {
    const seq = [
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
    expect(e.key(LogicalKeyboardKey.keyX), isNull);
    Reaction? r;
    for (final k in seq) {
      r = e.key(k);
    }
    expect(r!.fx, LoquetFx.backflip);
    for (final k in seq) {
      r = e.key(k);
    }
    expect(r, isNull);
  });

  test('five idle minutes doze off; first activity wakes', () {
    expect(e.handle(const UserIdle())!.mood, LoquetMood.sleep);
    final w = e.wake()!;
    expect((w.mood, w.line), (LoquetMood.cheerful, null));
  });

  test('milestone hook for later events', () {
    expect(e.milestone('sharedVault', LineKey.sharedVault)!.important, isTrue);
    expect(e.milestone('sharedVault', LineKey.sharedVault), isNull);
  });
}
