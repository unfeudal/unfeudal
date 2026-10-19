// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/orgs/host_binding.dart';
import 'package:unfeudal_client/src/ui/hosts/host_editor_panel.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  test('a perMember org host connects with the caller\'s bound personal key; unbound is MissingBinding', () async {
    final h = SyncHarness();
    final acc = await h.createAccount('camille@example.org', 'password-123');
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final s = testAppState(harness: h, ssh: ssh)
      ..dialogs = (FakeDialogs()..accept = true);
    await s.boot();
    await s.login(
      server: h.baseUrl,
      email: 'camille@example.org',
      password: 'password-123',
    );
    h.orgMembers[testOrgId] = {acc.userId};
    final f = newId(), keys = FolderKeys.generate(1);
    final host = h.serverPutOrg(
      await sealOrgItem(
        keys,
        folderId: f,
        meta: {
          ...hostJson('db', user: 'deploy'),
          'identityMode': 'perMember',
        },
      ),
    );
    h.orgBlock = orgBlock(
      members: [memberRow(acc.userId)],
      folderTree: [node(f)],
      acl: [
        aclRow(f, acc.userId, allow: ['connect']),
      ],
      wrappedKeys: [await wrappedRow(keys, f, acc.bundle.publicKey)],
      itemIds: [host.id],
    );
    await s.sync!.syncNow();
    final unbound = await s.connect(host.id);
    expect(unbound.error, isA<MissingBinding>());
    final mine = await s.vault!.upsertItem(
      type: 'identity',
      meta: {
        'schemaVersion': 1,
        'name': 'me',
        'kind': 'password',
        'publicKey': null,
      },
      secret: {
        'schemaVersion': 1,
        'kind': 'password',
        'privateKeyPem': null,
        'passphrase': null,
        'password': 'mine',
      },
    );
    await bindHost(s.vault!, host.id, mine);
    expect(bindingFor(s.vault!, host.id), mine);
    final binding = s.mirror!
        .outbox()
        .map((e) => e.item)
        .singleWhere((i) => i.type == 'hostBinding');
    expect((binding.scope, binding.folderId), (ItemScope.personal, null));
    await s.connect(host.id);
    expect(ssh.targets.last.identity!.password, 'mine');
    await bindHost(s.vault!, host.id, mine);
    expect(
      s.vault!.ofKind(ItemKind.hostBinding),
      hasLength(1),
      reason: 'one binding per host, updated in place',
    );
  });

  testWidgets(
    'the host editor offers the binding field for perMember org hosts only',
    (t) async {
      final h = SyncHarness(capabilities: ['orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      late Item host;
      late String personal, mine;
      await t.runAsync(() async {
        final me = s.stored!.userId;
        h.orgMembers[testOrgId] = {me};
        final f = newId(), keys = FolderKeys.generate(1);
        host = h.serverPutOrg(
          await sealOrgItem(
            keys,
            folderId: f,
            meta: {
              ...hostJson('db', user: 'deploy'),
              'identityMode': 'perMember',
            },
          ),
        );
        h.orgBlock = orgBlock(
          members: [memberRow(me)],
          folderTree: [node(f)],
          acl: [
            aclRow(f, me, allow: ['edit', 'connect']),
          ],
          wrappedKeys: [
            await wrappedRow(keys, f, h.accounts.values.first.bundle.publicKey),
          ],
          itemIds: [host.id],
        );
        await s.sync!.syncNow();
        mine = await s.vault!.upsertItem(
          type: 'identity',
          meta: {
            'schemaVersion': 1,
            'name': 'me',
            'kind': 'password',
            'publicKey': null,
          },
          secret: {
            'schemaVersion': 1,
            'kind': 'password',
            'privateKeyPem': null,
            'passphrase': null,
            'password': 'mine',
          },
        );
        personal = await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson('home'),
        );
      });
      await pumpApp(
        t,
        state: s,
        child: HostEditorPanel(hostId: host.id),
      );
      expect(find.byKey(const Key('binding-identity')), findsOneWidget);
      await t.tap(find.byKey(const Key('binding-identity')));
      await t.pumpAndSettle();
      await t.tap(find.text('me').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('host-save')));
      await pumpReal(t);
      expect(bindingFor(s.vault!, host.id), mine);
      await pumpApp(
        t,
        state: s,
        child: HostEditorPanel(hostId: personal),
      );
      expect(find.byKey(const Key('binding-identity')), findsNothing);
    },
  );
}
