// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/ui/snippets/snippets_screen.dart';
import 'package:unfeudal_client/src/vault/snippet_store.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets(
    'org vault: its snippets, read-only without edit; a new one goes to an editable org folder',
    (t) async {
      final h = SyncHarness(capabilities: ['orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      final keys = FolderKeys.generate(1), ro = newId(), rw = newId();
      h.orgMembers[testOrgId] = {me};
      late Item snippet;
      await t.runAsync(() async {
        final pub = h.accounts.values.first.bundle.publicKey;
        snippet = h.serverPutOrg(
          await sealOrgItem(
            keys,
            type: 'snippet',
            folderId: ro,
            meta: {
              'schemaVersion': 1,
              'name': 'org uptime',
              'command': 'uptime',
              'tags': <String>[],
            },
          ),
        );
        final folders = [
          h.serverPutOrg(
            await sealOrgItem(
              keys,
              id: ro,
              type: 'folder',
              meta: folderJson('Read'),
            ),
          ),
          h.serverPutOrg(
            await sealOrgItem(
              keys,
              id: rw,
              type: 'folder',
              meta: folderJson('Ops'),
            ),
          ),
        ];
        h.orgBlock = orgBlock(
          members: [memberRow(me)],
          folderTree: [node(ro), node(rw)],
          acl: [
            aclRow(ro, me, allow: ['view']),
            aclRow(rw, me, allow: ['view', 'edit']),
          ],
          wrappedKeys: [
            await wrappedRow(keys, ro, pub),
            await wrappedRow(keys, rw, pub),
          ],
          itemIds: [snippet.id, ...folders.map((e) => e.id)],
        );
        await s.sync!.syncNow();
      });
      s.orgs!.select(testOrgId);
      await pumpApp(t, state: s, child: const SnippetsScreen());
      await pumpReal(t);
      for (final k in [
        'snippet-edit-${snippet.id}',
        'snippet-delete-${snippet.id}',
      ]) {
        expect(pressed(t, k), isNull, reason: k);
      }
      await t.tap(find.byKey(const Key('snippet-new')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('snippet-name')), 'deploy');
      await t.enterText(
        find.byKey(const Key('snippet-command')),
        'make deploy',
      );
      await t.tap(find.byKey(const Key('snippet-location')));
      await t.pumpAndSettle();
      expect(
        find.byKey(Key('snippet-location-$ro')),
        findsNothing,
        reason: 'view only',
      );
      await t.tap(find.byKey(Key('snippet-location-$rw')).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('snippet-save')));
      await pumpReal(t, rounds: 10);
      await t.runAsync(() => s.sync!.syncNow());
      final made = s.vault!
          .ofKind(ItemKind.snippet)
          .firstWhere((e) => e.name == 'deploy');
      expect((made.orgId, made.folderId), (testOrgId, rw));
    },
  );

  testWidgets(
    'create: name and command required, command kept as typed, tags split',
    (t) async {
      final s = await signedInState(t);
      await pumpApp(t, state: s, child: const SnippetsScreen());
      final l = AppLocalizations.of(t.element(find.byType(SnippetsScreen)));
      expect(find.text(l.snippetsEmpty), findsOneWidget);
      await t.tap(find.byKey(const Key('snippet-new')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('snippet-save')));
      await t.pump();
      expect(find.text(l.fieldRequired), findsNWidgets(2));
      await t.enterText(find.byKey(const Key('snippet-name')), 'Deploy');
      await t.enterText(
        find.byKey(const Key('snippet-command')),
        '  cd /srv\nmake\n',
      );
      await t.enterText(find.byKey(const Key('snippet-tags')), 'ops, web');
      await t.tap(find.byKey(const Key('snippet-save')));
      await pumpReal(t, rounds: 10);
      final e = SnippetStore(s.vault!).list().single;
      expect((e.meta.name, e.meta.command), ('Deploy', '  cd /srv\nmake\n'));
      expect(e.meta.tags, ['ops', 'web']);
    },
  );

  testWidgets('insert into the active tab without Enter; multi-line asks', (
    t,
  ) async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final s = await signedInState(t, ssh: ssh);
    late String disk, deploy;
    await t.runAsync(() async {
      final web = await s.vault!.upsertItem(
        type: 'host',
        meta: hostJson('web', user: 'root'),
      );
      await s.vault!.hostKeys.pin(web, 'ssh-ed25519', 'SHA256:${'A' * 43}');
      await s.connections.connect(web);
      final store = SnippetStore(s.vault!);
      disk = await store.save(
        SnippetMeta(name: 'Disk', command: 'df -h\n', tags: []),
      );
      deploy = await store.save(
        SnippetMeta(name: 'Deploy', command: 'cd /srv\nmake', tags: ['ops']),
      );
    });
    await pumpApp(t, state: s);
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(const Key('section-snippets')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('snippets-search')), 'ops');
    await t.pump();
    expect(find.byKey(Key('snippet-insert-$disk')), findsNothing);
    await t.enterText(find.byKey(const Key('snippets-search')), '');
    await t.pump();
    final shell = ssh.shells.single;
    await t.tap(find.byKey(Key('snippet-insert-$disk')));
    await pumpReal(t, rounds: 3);
    expect(utf8.decode(shell.written.last), 'df -h');
    await t.tap(find.byKey(Key('snippet-insert-$deploy')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('multiline-send')));
    await pumpReal(t, rounds: 3);
    // Paste sends a line break as \r.
    expect(utf8.decode(shell.written.last), 'cd /srv\rmake');
  });

  testWidgets(
    'no connected tab: insert disabled; read-only: new, edit and delete disabled',
    (t) async {
      final h = SyncHarness(minClient: '9.0.0');
      final s = await signedInState(t, harness: h);
      late String id;
      await t.runAsync(() async {
        final item = await sealItem(
          h.accounts[testEmail]!.account!.unlocked.userKey,
          type: 'snippet',
          meta: {
            'schemaVersion': 1,
            'name': 'Disk',
            'command': 'df -h',
            'tags': <String>[],
          },
        );
        s.mirror!.upsertItems([item]);
        id = item.id;
        await s.vault!.reload();
        await s.sync!.syncNow();
      });
      await pumpApp(t, state: s, child: const SnippetsScreen());
      await t.pump();
      final l = AppLocalizations.of(t.element(find.byType(SnippetsScreen)));
      expect(find.text(l.snippetNoTerminal), findsOneWidget);
      for (final key in [
        'snippet-insert-$id',
        'snippet-new',
        'snippet-edit-$id',
        'snippet-delete-$id',
      ]) {
        expect(pressed(t, key), isNull, reason: key);
      }
    },
  );
}

/// The callback of a text or icon button, null when disabled.
VoidCallback? pressed(WidgetTester t, String key) =>
    switch (t.widget(find.byKey(Key(key)))) {
      final ButtonStyleButton b => b.onPressed,
      final IconButton b => b.onPressed,
      final other => throw StateError('not a button: $other'),
    };
