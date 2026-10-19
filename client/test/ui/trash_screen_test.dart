// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/history/trash_screen.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  Future<(SyncHarness, AppState, String, String)> world(
    WidgetTester t, {
    Map<String, Object?> info = const {},
  }) async {
    final h = SyncHarness(infoExtra: info);
    final s = await signedInState(t, harness: h);
    late String gone, kept;
    await t.runAsync(() async {
      gone = await s.vault!.upsertItem(type: 'host', meta: hostJson('old-ftp'));
      kept = await s.vault!.upsertItem(type: 'host', meta: hostJson('web'));
      await s.sync!.syncNow();
      await s.vault!.trashItem(gone);
      await s.sync!.syncNow();
    });
    return (h, s, gone, kept);
  }

  testWidgets(
    'lists trashed items with their purge date; restore puts them back',
    (t) async {
      final (h, s, gone, kept) = await world(t);
      await pumpApp(t, state: s, child: const TrashScreen());
      await pumpReal(t);
      expect(
        [find.byKey(Key('trash-$gone')), find.byKey(Key('trash-$kept'))],
        [findsOneWidget, findsNothing],
      );
      expect(find.textContaining('Deleted for good on'), findsOneWidget);
      await t.tap(find.byKey(Key('trash-restore-$gone')));
      await pumpReal(t);
      await t.runAsync(() => s.sync!.syncNow());
      await t.pump();
      expect(h.serverItem(gone)!.deleted, isFalse);
      expect(find.text('The trash is empty.'), findsOneWidget);
    },
  );

  testWidgets(
    'trashDays 0: kept until restored; a read-only server disables restore',
    (t) async {
      final (h, s, gone, _) = await world(t, info: {'trashDays': 0});
      h.minClient = '9.0.0';
      await t.runAsync(() => s.sync!.syncNow());
      await pumpApp(t, state: s, child: const TrashScreen());
      await pumpReal(t);
      expect(find.text('Kept until restored.'), findsOneWidget);
      expect(
        t.widget<TextButton>(find.byKey(Key('trash-restore-$gone'))).onPressed,
        isNull,
      );
    },
  );

  testWidgets('the rail opens the trash', (t) async {
    final (_, s, gone, _) = await world(t);
    await pumpApp(t, state: s, child: const HomeShell());
    await pumpReal(t);
    await t.tap(find.byKey(const Key('rail-trash')));
    await pumpReal(t);
    expect(find.byKey(Key('trash-$gone')), findsOneWidget);
  });
}
