// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/history/item_history_panel.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

const pw = {
  'schemaVersion': 1,
  'name': 'root',
  'kind': 'password',
  'publicKey': null,
};
Map<String, Object?> pwSecret(String p) => {
  'schemaVersion': 1,
  'kind': 'password',
  'privateKeyPem': null,
  'passphrase': null,
  'password': p,
};

void main() {
  testWidgets(
    'versions newest first with a field diff; restore writes the old content as a new revision',
    (t) async {
      final h = SyncHarness(capabilities: ['item_history', 'sync']);
      final s = await signedInState(t, harness: h);
      late String id;
      await t.runAsync(() async {
        id = await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson('web', address: '10.0.0.1'),
        );
        await s.sync!.syncNow();
        await s.vault!.upsertItem(
          id: id,
          type: 'host',
          meta: hostJson('web-2', address: '10.0.0.1'),
        );
        await s.sync!.syncNow();
      });
      await pumpApp(
        t,
        state: s,
        child: ItemHistoryPanel(itemId: id),
      );
      await pumpReal(t);
      expect([
        find.byKey(const Key('history-rev-2')),
        find.byKey(const Key('history-rev-1')),
      ], everyElement(findsOneWidget));
      expect(find.text('web → web-2'), findsOneWidget);
      await t.tap(find.byKey(const Key('history-restore-1')));
      await t.pump();
      await t.tap(find.byKey(const Key('confirm-yes')));
      await pumpReal(t);
      await t.runAsync(() => s.sync!.syncNow());
      final server = h.serverItem(id)!;
      expect(server.revision, 3);
      await t.runAsync(
        () async => expect(
          (await s.vault!.open(
            server,
            PayloadPart.meta,
            fromServer: false,
          ))!.json['name'],
          'web',
        ),
      );
    },
  );

  testWidgets(
    'a version whose secret does not open is never restored without it',
    (t) async {
      final h = SyncHarness(capabilities: ['item_history', 'sync']);
      final s = await signedInState(t, harness: h);
      late String id;
      await t.runAsync(() async {
        id = await s.vault!.upsertItem(
          type: 'identity',
          meta: pw,
          secret: pwSecret('old'),
        );
        await s.sync!.syncNow();
        await s.vault!.upsertItem(
          id: id,
          type: 'identity',
          meta: {...pw, 'name': 'root-2'},
          secret: pwSecret('new'),
        );
        await s.sync!.syncNow();
      });
      // the old secret was sealed under a key this device no longer holds
      final old = h.revisionsOf[id]!.single;
      final stranger = await sealItem(
        SymmetricCipher.newKey(),
        id: id,
        type: 'identity',
        meta: pw,
        secret: pwSecret('old'),
      );
      h.revisionsOf[id] = [
        Item.fromJson({...old.toJson(), 'secret': stranger.secret!.toJson()}),
      ];
      await pumpApp(
        t,
        state: s,
        child: ItemHistoryPanel(itemId: id),
      );
      await pumpReal(t);
      await t.tap(find.byKey(const Key('history-restore-1')));
      await t.pump();
      await t.tap(find.byKey(const Key('confirm-yes')));
      await pumpReal(t);
      expect(find.byKey(const Key('history-error')), findsOneWidget);
      await t.runAsync(() => s.sync!.syncNow());
      expect(h.serverItem(id)!.revision, 2, reason: 'nothing written');
    },
  );

  testWidgets(
    'secrets stay hidden without reveal; revealing shows them and reports it',
    (t) async {
      for (final caps in [
        ['client_events', 'item_history', 'sync'],
        ['client_events', 'item_history', 'reveal', 'sync'],
      ]) {
        final h = SyncHarness(capabilities: caps);
        final s = await signedInState(t, harness: h);
        late String id;
        await t.runAsync(() async {
          id = await s.vault!.upsertItem(
            type: 'identity',
            meta: pw,
            secret: pwSecret('old'),
          );
          await s.sync!.syncNow();
          await s.vault!.upsertItem(
            id: id,
            type: 'identity',
            meta: pw,
            secret: pwSecret('new'),
          );
          await s.sync!.syncNow();
        });
        await pumpApp(
          t,
          state: s,
          child: ItemHistoryPanel(itemId: id),
        );
        await pumpReal(t);
        expect([
          find.textContaining('old'),
          find.textContaining('new'),
        ], everyElement(findsNothing));
        if (!caps.contains('reveal')) {
          expect(find.byKey(const Key('history-reveal-2')), findsNothing);
          continue;
        }
        await t.tap(find.byKey(const Key('history-reveal-2')));
        await pumpReal(t);
        expect(find.text('old → new'), findsOneWidget);
        expect(h.reported.map((r) => r.body).toList(), [
          {'itemId': id},
        ]);
      }
    },
  );

  testWidgets('canReveal: reveal on the folder for org items', (t) async {
    final h = SyncHarness(capabilities: ['orgs', 'reveal', 'sync']);
    final s = await signedInState(t, harness: h);
    final me = s.stored!.userId;
    final f = newId();
    late Item orgItem;
    Future<void> block(int cursor, List<String> allow) => t.runAsync(() async {
      h.orgBlock = orgBlock(
        cursor: cursor,
        members: [memberRow(me, status: 'confirmed')],
        folderTree: [node(f)],
        acl: [aclRow(f, me, allow: allow)],
      );
      await s.sync!.syncNow();
    });
    await t.runAsync(
      () async => orgItem = await sealOrgItem(
        FolderKeys.generate(1),
        folderId: f,
        meta: hostJson('db'),
      ),
    );
    await block(1, ['connect']);
    expect(s.orgs!.canReveal(VaultEntry(orgItem, EntryState.ok)), isFalse);
    await block(2, ['reveal']);
    expect(s.orgs!.canReveal(VaultEntry(orgItem, EntryState.ok)), isTrue);
    expect(
      s.orgs!.canReveal(VaultEntry(wireItem(newId()), EntryState.ok)),
      isTrue,
      reason: 'personal items',
    );
  });
}
