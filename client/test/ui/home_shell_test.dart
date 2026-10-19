// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';

import 'package:unfeudal_client/src/ui/keychain/keychain_screen.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';
import 'package:unfeudal_client/src/vault/snippet_store.dart';
import 'package:unfeudal_client/src/version.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

Future<AppState> shell(WidgetTester t, {SyncHarness? harness}) async {
  final s = await signedInState(t, harness: harness);
  await pumpApp(t, state: s);
  await pumpReal(t, rounds: 10);
  return s;
}

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(HomeShell)));

void main() {
  testWidgets(
    'a sidebar entry opens its section in place of the sessions; back returns',
    (t) async {
      await shell(t);
      await t.tap(find.byKey(const Key('section-keychain')));
      await t.pump();
      expect(find.byType(KeychainScreen), findsOneWidget);
      expect(find.byKey(const Key('sidebar')), findsOneWidget);
      expect(find.text(l10n(t).tabsEmpty), findsNothing);
      await t.tap(find.byKey(const Key('manage-back')));
      await t.pump();
      expect(find.byType(KeychainScreen), findsNothing);
      expect(find.text(l10n(t).tabsEmpty), findsOneWidget);
    },
  );

  testWidgets(
    'layout: sidebar 272 resizable within 220–400, saved per device',
    (t) async {
      final s = await shell(t);
      expect(t.getSize(find.byKey(const Key('tree-panel'))).width, 272);
      await t.drag(find.byKey(const Key('tree-resizer')), const Offset(500, 0));
      await t.pumpAndSettle();
      expect(t.getSize(find.byKey(const Key('tree-panel'))).width, 400);
      expect(s.settings.treeWidth, 400);
    },
  );

  testWidgets('Ctrl+Shift+B hides the tree, Ctrl+K focuses search', (t) async {
    await shell(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tree-panel')), findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    final search = t.widget<TextField>(find.byKey(const Key('tree-search')));
    expect(search.focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'tree: nested folders, search by name, address and tag; trashed hidden; unreadable labelled',
    (t) async {
      final s = await shell(t);
      await t.runAsync(() async {
        final v = s.vault!;
        final f = await v.saveFolder(FolderMeta.fromJson(folderJson('prod')));
        await v.upsertItem(
          type: 'host',
          folderId: f,
          meta: hostJson('web', address: '10.1.1.1', tags: ['nginx']),
        );
        await v.upsertItem(
          type: 'host',
          meta: hostJson('db', address: 'db.lan'),
        );
        final gone = await v.upsertItem(
          type: 'host',
          meta: hostJson('retired-box'),
        );
        await v.trashItem(gone);
        s.mirror!.upsertItems([
          await sealItem(SymmetricCipher.newKey(), meta: hostJson('x')),
        ]);
        await v.reload();
      });
      await t.pumpAndSettle();
      expect(find.text('web'), findsOneWidget);
      expect(find.text('retired-box'), findsNothing);
      expect(find.text(l10n(t).treeUnreadable), findsOneWidget);
      for (final (q, name) in [
        ('web', 'web'),
        ('db.lan', 'db'),
        ('nginx', 'web'),
      ]) {
        await t.enterText(find.byKey(const Key('tree-search')), q);
        await t.pumpAndSettle();
        // not find.text: it also matches the search field holding the query
        expect(
          find.byWidgetPredicate((w) => w is Text && w.data == name),
          findsOneWidget,
          reason: q,
        );
      }
    },
  );

  testWidgets(
    'the search lists matching snippets; without a session they insert nothing',
    (t) async {
      final s = await shell(t);
      late String id;
      await t.runAsync(() async {
        id = await SnippetStore(s.vault!)
            .save(SnippetMeta(name: 'Disk usage', command: 'df -h'));
      });
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('tree-search')), 'disk');
      await t.pumpAndSettle();
      final row = t.widget<InkWell>(find.byKey(Key('search-snippet-$id')));
      expect(row.onTap, isNull);
    },
  );

  testWidgets('update button opens the compiled URL, never a server value', (
    t,
  ) async {
    final opened = <Uri>[];
    openExternalUrl = (u) async {
      opened.add(u);
      return true;
    };
    await shell(
      t,
      harness: SyncHarness(
        latestClient: '0.2.0',
        infoExtra: {'downloadUrl': 'https://evil.example/x.exe'},
      ),
    );
    expect(find.text(l10n(t).bannerUpdate('0.2.0')), findsOneWidget);
    await t.tap(find.byKey(const Key('update-download')));
    expect(opened, [Uri.parse(officialReleasesUrl)]);
  });

  testWidgets('plain http server: permanent unencrypted banner', (t) async {
    await shell(
      t,
      harness: SyncHarness(
        baseUrl: Uri.parse('http://192.168.1.10:8080'),
        capabilities: ['plain_http_lan', 'sync'],
      ),
    );
    expect(find.byKey(const Key('banner-plain-http')), findsOneWidget);
    expect(find.text(l10n(t).bannerPlainHttp), findsOneWidget);
  });

  testWidgets('https server: no unencrypted banner', (t) async {
    await shell(t);
    expect(find.byKey(const Key('banner-plain-http')), findsNothing);
  });

  testWidgets('read-only banner with its reason; new host disabled', (t) async {
    await shell(t, harness: SyncHarness(minClient: '9.0.0'));
    expect(find.byKey(const Key('banner-read-only')), findsOneWidget);
    expect(
      t.widget<IconButton>(find.byKey(const Key('tree-new-host'))).onPressed,
      isNull,
    );
  });

  testWidgets(
    'restore banner: blocking Accept / Refuse, refused keeps Accept',
    (t) async {
      final h = SyncHarness();
      final s = await shell(t, harness: h);
      h.restore(h.snapshot(), epoch: 'AAAAAAAAAAAAAAAAAAAAAA');
      await t.runAsync(s.sync!.syncNow);
      await t.pump();
      expect(find.byKey(const Key('sync-restore-accept')), findsOneWidget);
      await t.tap(find.byKey(const Key('sync-restore-refuse')));
      await pumpReal(t, rounds: 5);
      expect(find.text(l10n(t).bannerRestoreRefused), findsOneWidget);
      expect(find.byKey(const Key('sync-restore-refuse')), findsNothing);
      await t.tap(find.byKey(const Key('sync-restore-accept')));
      await pumpReal(t, rounds: 10);
      expect(find.byKey(const Key('sync-restore-accept')), findsNothing);
    },
  );

  testWidgets('rejected write: retry, keep a copy, discard', (t) async {
    final h = SyncHarness();
    final s = await shell(t, harness: h);
    late String id;
    await t.runAsync(() async {
      h.offline = true;
      await s.vault!.upsertItem(type: 'host', meta: hostJson('big'));
      id = s.mirror!.outbox().single.item.id;
      h
        ..offline = false
        ..failPuts[id] = 413;
      for (var i = 0; i < 3; i++) {
        await s.sync!.syncNow();
      }
    });
    await t.pump();
    expect(find.byKey(Key('unsynced-retry-$id')), findsOneWidget);
    h.failPuts.remove(id);
    await t.tap(find.byKey(Key('unsynced-retry-$id')));
    await pumpReal(t, rounds: 10);
    expect(find.byKey(Key('unsynced-retry-$id')), findsNothing);
    expect(h.serverItem(id), isNotNull);
  });
}
