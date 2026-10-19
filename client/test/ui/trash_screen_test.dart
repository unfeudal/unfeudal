// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/history/trash_screen.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
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

  testWidgets('an org item is restorable only with edit on its folder', (
    t,
  ) async {
    for (final (allow, enabled) in [
      (['view'], false),
      (['view', 'edit'], true),
    ]) {
      final h = SyncHarness(capabilities: ['orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      final keys = FolderKeys.generate(1), f = newId();
      h.orgMembers[testOrgId] = {me};
      late Item host;
      await t.runAsync(() async {
        final pub = h.accounts.values.first.bundle.publicKey;
        host = h.serverPutOrg(
          await sealOrgItem(
            keys,
            folderId: f,
            meta: hostJson('org-db'),
            deleted: true,
          ),
        );
        final folder = h.serverPutOrg(
          await sealOrgItem(keys, id: f, type: 'folder', meta: folderJson('P')),
        );
        h.orgBlock = orgBlock(
          members: [memberRow(me)],
          folderTree: [node(f)],
          acl: [aclRow(f, me, allow: allow)],
          wrappedKeys: [await wrappedRow(keys, f, pub)],
          itemIds: [host.id, folder.id],
        );
        await s.sync!.syncNow();
      });
      await pumpApp(t, state: s, child: const TrashScreen());
      await pumpReal(t);
      expect(
        t
                .widget<TextButton>(find.byKey(Key('trash-restore-${host.id}')))
                .onPressed !=
            null,
        enabled,
        reason: '$allow',
      );
    }
  });

  testWidgets(
    'a trashed org folder shows what is inside; an item moves out to a live folder',
    (t) async {
      final h = SyncHarness(capabilities: ['orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      final keys = FolderKeys.generate(1), gone = newId(), live = newId();
      h.orgMembers[testOrgId] = {me};
      late Item host;
      await t.runAsync(() async {
        final pub = h.accounts.values.first.bundle.publicKey;
        host = h.serverPutOrg(
          await sealOrgItem(keys, folderId: gone, meta: hostJson('db')),
        );
        final folders = [
          h.serverPutOrg(
            await sealOrgItem(
              keys,
              id: gone,
              type: 'folder',
              meta: folderJson('Old'),
              deleted: true,
            ),
          ),
          h.serverPutOrg(
            await sealOrgItem(
              keys,
              id: live,
              type: 'folder',
              meta: folderJson('Prod'),
            ),
          ),
        ];
        h.orgBlock = orgBlock(
          members: [memberRow(me)],
          folderTree: [node(gone), node(live)],
          acl: [
            aclRow(gone, me, allow: ['view', 'edit']),
            aclRow(live, me, allow: ['view', 'edit']),
          ],
          wrappedKeys: [
            await wrappedRow(keys, gone, pub),
            await wrappedRow(keys, live, pub),
          ],
          itemIds: [host.id, ...folders.map((e) => e.id)],
        );
        await s.sync!.syncNow();
      });
      await pumpApp(t, state: s, child: const TrashScreen());
      await pumpReal(t);
      expect(find.byKey(Key('trash-inside-${host.id}')), findsOneWidget);
      await t.tap(find.byKey(Key('trash-move-out-${host.id}')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trash-move-out-dest')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('trash-move-out-dest-$live')).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trash-move-out-save')));
      await pumpReal(t);
      await t.runAsync(() => s.sync!.syncNow());
      expect(h.serverItem(host.id)!.folderId, live);
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
