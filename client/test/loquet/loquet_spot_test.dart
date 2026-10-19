// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/logo.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/loquet.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/loquet/loquet_spot.dart';
import 'package:unfeudal_client/src/loquet/reaction_engine.dart';
import 'package:unfeudal_client/src/settings/settings.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets('no AppScope above: the logo', (t) async {
    await t.pumpWidget(
      const MaterialApp(home: LoquetSpot(placement: LoquetPlacement.empty)),
    );
    expect(find.byType(UfLogo), findsOneWidget);
    expect(find.byType(Loquet), findsNothing);
  });

  testWidgets('placement sets the size; the controller sets the mood', (
    t,
  ) async {
    final s = await signedInState(t);
    await pumpApp(
      t,
      state: s,
      child: const LoquetSpot(placement: LoquetPlacement.sidebar),
    );
    expect(t.getSize(find.byType(Loquet)), const Size(28, 28));
    s.loquet.show(const Reaction(LoquetMood.happy));
    await t.pump();
    expect(t.widget<Loquet>(find.byType(Loquet)).mood, LoquetMood.happy);
  });

  testWidgets('mascot off on the server: the logo', (t) async {
    final s = await signedInState(
      t,
      harness: SyncHarness(capabilities: const ['sync']),
    );
    await pumpApp(
      t,
      state: s,
      child: const LoquetSpot(placement: LoquetPlacement.sidebar),
    );
    expect(find.byType(UfLogo), findsOneWidget);
  });

  testWidgets('a line shows a bubble; sober never does', (t) async {
    final s = await signedInState(t);
    await pumpApp(
      t,
      state: s,
      child: const LoquetSpot(placement: LoquetPlacement.lock),
    );
    s.loquet.show(const Reaction(LoquetMood.happy, line: LineKey.lock));
    await t.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('loquet-bubble')),
        matching: find.text('Shut tight.'),
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('loquet-bubble')), findsNothing);
    await t.runAsync(
      () => s.updateSettings(s.settings.copyWith(loquetMode: LoquetMode.sober)),
    );
    s.loquet.show(s.loquet.engine.handle(const VaultLocked()));
    await t.pump();
    expect(find.byKey(const Key('loquet-bubble')), findsNothing);
    expect(find.byType(Loquet), findsOneWidget);
  });

  testWidgets('rebuilds keep the chosen variant', (t) async {
    final s = await signedInState(t);
    await pumpApp(
      t,
      state: s,
      child: const LoquetSpot(
        placement: LoquetPlacement.lock,
        line: LineKey.idleClick,
      ),
    );
    String bubble() => t
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('loquet-bubble')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final first = bubble();
    for (var i = 0; i < 3; i++) {
      s.loquet.watch(i / 3); // the controller notifies, the spot rebuilds
      await t.pump();
      expect(bubble(), first);
    }
  });

  testWidgets(
    'the title bar never shows a bubble (it would cover the terminal)',
    (t) async {
      final s = await signedInState(t);
      await pumpApp(
        t,
        state: s,
        child: const LoquetSpot(placement: LoquetPlacement.titleBar),
      );
      s.loquet.show(const Reaction(LoquetMood.happy, line: LineKey.lock));
      await t.pump();
      expect(find.byKey(const Key('loquet-bubble')), findsNothing);
    },
  );

  testWidgets('a fixed mood and line override the controller', (t) async {
    final s = await signedInState(t);
    await pumpApp(
      t,
      state: s,
      child: const LoquetSpot(
        placement: LoquetPlacement.dialog,
        mood: LoquetMood.alert,
        line: LineKey.keyChanged,
      ),
    );
    expect(t.widget<Loquet>(find.byType(Loquet)).mood, LoquetMood.alert);
    expect(find.text('This key changed. Blocking.'), findsOneWidget);
  });

  testWidgets('tap emits LoquetClicked; performance mode is still', (t) async {
    final s = await signedInState(
      t,
      settings: const Settings(performanceMode: true),
    );
    final events = <AppEvent>[];
    s.events.listen(events.add);
    await pumpApp(
      t,
      state: s,
      child: const LoquetSpot(placement: LoquetPlacement.sidebar),
    );
    expect(t.widget<Loquet>(find.byType(Loquet)).still, isTrue);
    await t.tap(find.byType(Loquet));
    await t.pump();
    expect(events.whereType<LoquetClicked>(), hasLength(1));
  });
}
