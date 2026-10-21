// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/field.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/ui/hosts/editor_frame.dart';
import 'package:unfeudal_client/src/ui/hosts/folder_editor_panel.dart';
import 'package:unfeudal_client/src/ui/hosts/host_binding_field.dart';
import 'package:unfeudal_client/src/ui/hosts/host_editor_panel.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(EditorFrame).first));

/// The text under a field: its source line or error.
Finder underField(String key, String text) => find.descendant(
  of: find.ancestor(of: find.byKey(Key(key)), matching: find.byType(UfField)),
  matching: find.text(text),
);

/// An org host in folder `Prod`, synced for a member with [allow] on that folder.
Future<({AppState state, String me, String hostId, String folderId})> orgHost(
  WidgetTester t, {
  required List<String> allow,
}) async {
  final h = SyncHarness(capabilities: ['orgs', 'sync']);
  final s = await signedInState(t, harness: h);
  final me = s.stored!.userId;
  final keys = FolderKeys.generate(1), f = newId();
  h.orgMembers[testOrgId] = {me};
  late Item host;
  await t.runAsync(() async {
    final pub = h.accounts.values.first.bundle.publicKey;
    host = h.serverPutOrg(
      await sealOrgItem(keys, folderId: f, meta: hostJson('org-db')),
    );
    final folder = h.serverPutOrg(
      await sealOrgItem(keys, id: f, type: 'folder', meta: folderJson('Prod')),
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
  return (state: s, me: me, hostId: host.id, folderId: f);
}

void main() {
  testWidgets(
    'new host: required fields, an emptied port inherits, saved with HostCreated',
    (t) async {
      final s = await signedInState(t);
      final events = <AppEvent>[];
      s.events.listen(events.add);
      await pumpApp(t, state: s, child: const HostEditorPanel());
      await t.tap(find.byKey(const Key('host-save')));
      await t.pump();
      expect(find.text(l10n(t).fieldRequired), findsNWidgets(2));
      await t.enterText(find.byKey(const Key('host-name')), 'web');
      await t.enterText(find.byKey(const Key('host-address')), '10.0.0.5');
      await t.enterText(find.byKey(const Key('host-port')), '2222');
      await t.enterText(find.byKey(const Key('host-port')), '');
      await t.tap(find.byKey(const Key('host-save')));
      await pumpReal(t, rounds: 10);
      expect(s.vault!.ofKind(ItemKind.host).single.name, 'web');
      expect(
        s.vault!.ofKind(ItemKind.host).single.meta,
        isNot(contains('port')),
      );
      expect(events.whereType<HostCreated>().single.name, 'web');
    },
  );

  testWidgets('a new host is saved in the folder it was opened for', (t) async {
    final s = await signedInState(t);
    late String folder;
    await t.runAsync(
      () async => folder = await s.vault!.saveFolder(FolderMeta(name: 'Prod')),
    );
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(folderId: folder),
    );
    expect(find.byKey(const Key('host-folder')), findsNothing);
    await t.enterText(find.byKey(const Key('host-name')), 'web');
    await t.enterText(find.byKey(const Key('host-address')), '10.0.0.5');
    await t.tap(find.byKey(const Key('host-save')));
    await pumpReal(t, rounds: 10);
    expect(s.vault!.ofKind(ItemKind.host).single.folderId, folder);
  });

  testWidgets('a password added from the editor becomes the host identity', (
    t,
  ) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s, child: const HostEditorPanel());
    await t.tap(find.byKey(const Key('host-identity-password')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pw-name')), 'root pw');
    await t.enterText(find.byKey(const Key('pw-value')), 's3cret');
    await t.tap(find.byKey(const Key('pw-save')));
    await pumpReal(t, rounds: 10);
    await t.enterText(find.byKey(const Key('host-name')), 'web');
    await t.enterText(find.byKey(const Key('host-address')), '10.0.0.5');
    await t.tap(find.byKey(const Key('host-save')));
    await pumpReal(t, rounds: 10);
    final identity = s.vault!.ofKind(ItemKind.identity).single;
    expect(identity.name, 'root pw');
    expect(
      s.vault!.ofKind(ItemKind.host).single.meta!['identityId'],
      identity.id,
    );
  });

  testWidgets('inherited values are shown greyed with their source', (t) async {
    final s = await signedInState(t);
    late String host;
    await t.runAsync(() async {
      final top = await s.vault!.saveFolder(
        FolderMeta.fromJson(folderJson('top', port: 2222)),
      );
      host = await s.vault!.upsertItem(
        type: 'host',
        folderId: top,
        meta: hostJson('web'),
      );
    });
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: host),
    );
    final port = t.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('host-port')),
        matching: find.byType(TextField),
      ),
    );
    expect(port.decoration!.hintText, '2222');
    expect(
      underField('host-port', l10n(t).hostInherited('top')),
      findsOneWidget,
    );
    expect(underField('host-user', l10n(t).hostDefault), findsOneWidget);
  });

  testWidgets('saving keeps the fields this editor does not show', (t) async {
    final s = await signedInState(t);
    late String host;
    await t.runAsync(
      () async => host = await s.vault!.upsertItem(
        type: 'host',
        meta: {
          ...hostJson('web'),
          'forwards': [
            {
              'localPort': 8443,
              'remoteHost': '127.0.0.1',
              'remotePort': 443,
              'autoStart': false,
            },
          ],
          'jumpHostId': newId(),
          'colorLabel': 'red',
        },
      ),
    );
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: host),
    );
    await t.enterText(find.byKey(const Key('host-name')), 'web2');
    await t.tap(find.byKey(const Key('host-save')));
    await pumpReal(t, rounds: 10);
    final meta = s.vault!.entry(host)!.meta!;
    expect(meta['name'], 'web2');
    expect(meta['colorLabel'], 'red');
    expect((meta['forwards'] as List).length, 1);
    expect(meta['jumpHostId'], isNotNull);
    // inherited port and a personal host's identity mode are left out, not written as null / shared
    expect(meta.containsKey('port'), isFalse);
    expect(meta.containsKey('identityMode'), isFalse);
  });

  testWidgets('a host with a newer payload is read-only', (t) async {
    final h = SyncHarness();
    final s = await signedInState(t, harness: h);
    late String newer;
    await t.runAsync(() async {
      final item = await sealItem(
        h.accounts[testEmail]!.account!.unlocked.userKey,
        meta: {...hostJson('n'), 'schemaVersion': 2},
      );
      s.mirror!.upsertItems([item]);
      newer = item.id;
      await s.vault!.reload();
    });
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: newer),
    );
    expect(find.text(l10n(t).itemNewer), findsOneWidget);
    expect(find.byKey(const Key('host-save')), findsNothing);
  });

  testWidgets('a trashed host is read-only', (t) async {
    final s = await signedInState(t);
    late String trashed;
    await t.runAsync(() async {
      trashed = await s.vault!.upsertItem(type: 'host', meta: hostJson('t'));
      await s.vault!.trashItem(trashed);
    });
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: trashed),
    );
    expect(find.text(l10n(t).itemTrashed), findsOneWidget);
    expect(find.byKey(const Key('host-save')), findsNothing);
  });

  testWidgets('folder editor: the parent cannot be the folder or inside it', (
    t,
  ) async {
    final s = await signedInState(t);
    late String top, sub;
    await t.runAsync(() async {
      top = await s.vault!.saveFolder(FolderMeta.fromJson(folderJson('top')));
      sub = await s.vault!.saveFolder(
        FolderMeta.fromJson(folderJson('sub')),
        parentId: top,
      );
    });
    await pumpApp(
      t,
      state: s,
      child: FolderEditorPanel(folderId: top),
    );
    await t.tap(find.byKey(const Key('folder-parent')));
    await t.pumpAndSettle();
    expect(find.byKey(Key('folder-parent-$sub')), findsNothing);
    expect(find.byKey(Key('folder-parent-$top')), findsNothing);
  });

  testWidgets('folder editor: a confirmed delete trashes the subtree', (
    t,
  ) async {
    final s = await signedInState(t);
    late String top, sub;
    await t.runAsync(() async {
      top = await s.vault!.saveFolder(FolderMeta.fromJson(folderJson('top')));
      sub = await s.vault!.saveFolder(
        FolderMeta.fromJson(folderJson('sub')),
        parentId: top,
      );
    });
    await pumpApp(
      t,
      state: s,
      child: FolderEditorPanel(folderId: top),
    );
    await t.tap(find.byKey(const Key('folder-delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-yes')));
    await pumpReal(t, rounds: 10);
    expect((s.vault!.isTrashed(top), s.vault!.isTrashed(sub)), (true, true));
  });

  testWidgets(
    'Access tab: an org host lists its folder rights, no edit without manage; a personal host has no Access tab',
    (t) async {
      final org = await orgHost(t, allow: ['edit']);
      final s = org.state;
      late String personal;
      await t.runAsync(
        () async => personal = await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson('nas'),
        ),
      );
      await pumpApp(
        t,
        state: s,
        child: HostEditorPanel(hostId: org.hostId),
      );
      await t.tap(find.text(l10n(t).inspectorTabAccess));
      await t.pump();
      expect(find.byKey(Key('access-${org.me}')), findsOneWidget);
      expect(find.byKey(const Key('access-why')), findsOneWidget);
      expect(find.byKey(const Key('access-edit')), findsNothing);

      await pumpApp(
        t,
        state: s,
        child: HostEditorPanel(hostId: personal),
      );
      expect(find.text(l10n(t).inspectorTabAccess), findsNothing);
    },
  );

  testWidgets('a refused org host trash shows the problem and stays open', (
    t,
  ) async {
    final org = await orgHost(t, allow: ['view']);
    var closed = false;
    await pumpApp(
      t,
      state: org.state,
      child: HostEditorPanel(hostId: org.hostId, onClose: () => closed = true),
    );
    await t.tap(find.byKey(const Key('host-delete')));
    await pumpReal(t, rounds: 10);
    expect(find.byType(UfErrorLine, skipOffstage: false), findsOneWidget);
    expect(closed, isFalse);
  });

  testWidgets('a refused org folder trash shows the problem and stays open', (
    t,
  ) async {
    final org = await orgHost(t, allow: ['view']);
    var closed = false;
    await pumpApp(
      t,
      state: org.state,
      child: FolderEditorPanel(
        folderId: org.folderId,
        onClose: () => closed = true,
      ),
    );
    await t.tap(find.byKey(const Key('folder-delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-yes')));
    await pumpReal(t, rounds: 10);
    expect(find.byType(UfErrorLine), findsOneWidget);
    expect(closed, isFalse);
  });

  testWidgets('History tab: the versions listed inside the inspector', (
    t,
  ) async {
    final h = SyncHarness(capabilities: ['item_history', 'sync']);
    final s = await signedInState(t, harness: h);
    late String id;
    await t.runAsync(() async {
      id = await s.vault!.upsertItem(type: 'host', meta: hostJson('web'));
      await s.sync!.syncNow();
      await s.vault!.upsertItem(id: id, type: 'host', meta: hostJson('web-2'));
      await s.sync!.syncNow();
    });
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: id),
    );
    await t.tap(find.text(l10n(t).itemHistory));
    await pumpReal(t);
    expect([
      find.byKey(const Key('history-rev-2')),
      find.byKey(const Key('history-rev-1')),
    ], everyElement(findsOneWidget));
  });

  testWidgets('a failed key binding is reported', (t) async {
    final h = SyncHarness(minClient: '9.0.0');
    final s = await signedInState(t, harness: h);
    late String identity;
    await t.runAsync(() async {
      final item = await sealItem(
        h.accounts[testEmail]!.account!.unlocked.userKey,
        type: 'identity',
        meta: {
          'schemaVersion': 1,
          'name': 'me',
          'kind': 'password',
          'publicKey': null,
        },
      );
      s.mirror!.upsertItems([item]);
      identity = item.id;
      await s.vault!.reload();
      await s.sync!.syncNow();
    });
    await pumpApp(
      t,
      state: s,
      child: Scaffold(body: HostBindingField(hostId: newId())),
    );
    final l = AppLocalizations.of(t.element(find.byType(HostBindingField)));
    await t.tap(find.byKey(const Key('binding-identity')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('binding-identity-$identity')).last);
    await pumpReal(t, rounds: 10);
    expect(find.text(l.errorReadOnly), findsOneWidget);
  });
}
