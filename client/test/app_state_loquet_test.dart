// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';
import 'support/sync_harness.dart';

void main() {
  testWidgets('mode follows the server flag and the pref', (t) async {
    final s = await signedInState(
      t,
      settings: const Settings(loquetMode: LoquetMode.sober),
    );
    expect(s.loquet.mode, LoquetMode.sober);
    final off = await signedInState(
      t,
      harness: SyncHarness(capabilities: const ['recovery_kit', 'sync']),
    );
    expect(off.loquet.mode, LoquetMode.off);
    await t.runAsync(
      () =>
          off.updateSettings(off.settings.copyWith(loquetMode: LoquetMode.on)),
    );
    expect(off.loquet.mode, LoquetMode.off);
  });

  testWidgets('events reach Loquet; ConnectSucceeded counts in loquet.json', (
    t,
  ) async {
    final dir = Directory.systemTemp.createTempSync('loquet');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/loquet.json');
    final memory = (await t.runAsync(
      () => LoquetMemory.load(file, now: DateTime(2026, 10, 15)),
    ))!;
    final fileBacked = await signedInState(t, loquetMemory: memory);
    // in real time: the write the event starts is awaited, not a fixed delay
    await t.runAsync(() async {
      fileBacked.emit(const ConnectSucceeded(hostId: 'h', user: 'deploy'));
      await memory.save(); // queued behind that write
    });
    await t.pump();
    expect(fileBacked.loquet.mood, LoquetMood.happy);
    expect((jsonDecode(file.readAsStringSync()) as Map)['connections'], 1);
  });

  testWidgets('Loquet writes nothing to the outbox', (t) async {
    final s = await signedInState(t);
    final before = s.mirror!.outbox().length;
    for (final e in const [
      LoquetClicked(),
      UserIdle(),
      WentOffline(),
      CameOnline(),
      ThemeChanged(mode: ThemeMode.dark),
    ]) {
      s.emit(e);
    }
    await t.runAsync(pumpEventQueue);
    expect(s.mirror!.outbox().length, before);
  });

  testWidgets('terminal input only marks typing', (t) async {
    final h = SyncHarness();
    final s = await signedInState(t, harness: h);
    await t.runAsync(
      () => s.vault!.upsertItem(
        type: 'host',
        meta: hostJson('web', user: 'deploy'),
      ),
    );
    final hostId = s.vault!.ofKind(ItemKind.host).single.id;
    await t.runAsync(() => s.connections.connect(hostId));
    expect(s.loquet.engine.isTyping, isFalse);
    s.connections.tabs.single.onUserInput!();
    expect(s.loquet.engine.isTyping, isTrue);
  });

  testWidgets('activity wakes a dozing Loquet', (t) async {
    final s = await signedInState(t);
    s.emit(const UserIdle());
    await t.pump();
    expect(s.loquet.mood, LoquetMood.sleep);
    s.recordActivity();
    expect(s.loquet.mood, isNot(LoquetMood.sleep));
  });
}
