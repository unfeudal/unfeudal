// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/ui/snippets/snippets_panel.dart';
import 'package:unfeudal_client/src/vault/snippet_store.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets(
    'create: name and command required, command kept as typed, tags split',
    (t) async {
      final s = await signedInState(t);
      await pumpApp(t, state: s, child: const SnippetsPanel());
      final l = AppLocalizations.of(t.element(find.byType(SnippetsPanel)));
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

  testWidgets(
    'insert into the active tab without Enter; multi-line asks; SnippetInserted',
    (t) async {
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
        await s.vault!.pinHostKey(web, 'ssh-ed25519', 'SHA256:${'A' * 43}');
        await s.connect(web);
        final store = SnippetStore(s.vault!);
        disk = await store.save(
          SnippetMeta(name: 'Disk', command: 'df -h\n', tags: []),
        );
        deploy = await store.save(
          SnippetMeta(name: 'Deploy', command: 'cd /srv\nmake', tags: ['ops']),
        );
      });
      final events = <AppEvent>[];
      s.events.listen(events.add);
      await pumpApp(t, state: s);
      await pumpReal(t, rounds: 5);
      await t.tap(find.byKey(const Key('snippets-button')));
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
      expect(
        utf8.decode(shell.written.last),
        'cd /srv\rmake',
      ); // paste sends a line break as \r
      expect(events.whereType<SnippetInserted>().map((e) => e.snippetId), [
        disk,
        deploy,
      ]);
    },
  );

  testWidgets(
    'no connected tab: insert disabled; read-only: new, edit and delete disabled',
    (t) async {
      final s = await signedInState(
        t,
        harness: SyncHarness(minClient: '9.0.0'),
      );
      late String id;
      await t.runAsync(() async {
        final item = await sealItem(
          s.vault!.debugKey,
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
      await pumpApp(t, state: s, child: const SnippetsPanel());
      await t.pump();
      final l = AppLocalizations.of(t.element(find.byType(SnippetsPanel)));
      expect(find.text(l.snippetNoTerminal), findsOneWidget);
      for (final key in [
        'snippet-insert-$id',
        'snippet-new',
        'snippet-edit-$id',
        'snippet-delete-$id',
      ]) {
        expect(
          t.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed,
          isNull,
          reason: key,
        );
      }
    },
  );
}
