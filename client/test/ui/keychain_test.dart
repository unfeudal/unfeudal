// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/orgs/host_binding.dart';
import 'package:unfeudal_client/src/ui/keychain/keychain_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets(
    'shared org identities: listed per folder, created with edit, read-only without',
    (t) async {
      final h = SyncHarness(capabilities: ['orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      final keys = FolderKeys.generate(1), ro = newId(), rw = newId();
      h.orgMembers[testOrgId] = {me};
      await t.runAsync(() async {
        final pub = h.accounts.values.first.bundle.publicKey;
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
            aclRow(rw, me, allow: ['view', 'edit', 'connect']),
          ],
          wrappedKeys: [
            await wrappedRow(keys, ro, pub),
            await wrappedRow(keys, rw, pub),
          ],
          itemIds: folders.map((e) => e.id).toList(),
        );
        await s.sync!.syncNow();
      });
      s.orgs!.select(testOrgId);
      await pumpApp(t, state: s, child: const KeychainScreen());
      await pumpReal(t);
      Future<void> place(String id) async {
        await t.tap(find.byKey(const Key('keychain-place')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key('keychain-place-$id')).last);
        await t.pumpAndSettle();
      }

      await place(ro);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('key-password')))
            .onPressed,
        isNull,
      );
      await place(rw);
      await t.tap(find.byKey(const Key('key-password')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('pw-name')), 'shared root');
      await t.enterText(find.byKey(const Key('pw-value')), 'hunter2');
      await t.tap(find.byKey(const Key('pw-save')));
      await pumpReal(t, rounds: 10);
      final made = s.vault!.ofKind(ItemKind.identity).single;
      expect(
        (made.orgId, made.folderId, made.name),
        (testOrgId, rw, 'shared root'),
      );
      expect(find.text('shared root'), findsWidgets);
    },
  );

  testWidgets('generate Ed25519 (default) with a passphrase', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s, child: const KeychainScreen());
    await t.tap(find.byKey(const Key('key-generate')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('gen-name')), 'laptop');
    await t.enterText(find.byKey(const Key('gen-passphrase')), 'pp');
    await t.tap(find.byKey(const Key('gen-save')));
    await pumpReal(t, rounds: 40);
    final e = s.vault!.ofKind(ItemKind.identity).single;
    expect(e.meta!['kind'], 'privateKey');
    expect(e.meta!['publicKey'] as String, startsWith('ssh-ed25519 '));
    late IdentitySecret secret;
    await t.runAsync(
      () async => secret = (await s.vault!.identitySecret(e.id))!,
    );
    expect(secret.passphrase, 'pp');
  });

  testWidgets('import validates the key first; PuTTY refused', (t) async {
    final s = await signedInState(t);
    late GeneratedKey k;
    await t.runAsync(() async => k = await generateEd25519());
    await pumpApp(t, state: s, child: const KeychainScreen());
    final l = AppLocalizations.of(t.element(find.byType(KeychainScreen)));
    await t.tap(find.byKey(const Key('key-import')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('import-name')), 'putty');
    await t.enterText(
      find.byKey(const Key('import-pem')),
      'PuTTY-User-Key-File-3: ssh-ed25519',
    );
    await t.tap(find.byKey(const Key('import-save')));
    await pumpReal(t, rounds: 5);
    expect(find.text(l.errorInvalidKey), findsOneWidget);
    await t.enterText(find.byKey(const Key('import-pem')), k.privateKeyPem);
    await t.tap(find.byKey(const Key('import-save')));
    await pumpReal(t, rounds: 10);
    expect(
      s.vault!.ofKind(ItemKind.identity).single.meta!['publicKey'],
      startsWith(k.publicKey.split(' ').take(2).join(' ')),
    );
  });

  testWidgets('password identity; copy public key; rename keeps the secret', (
    t,
  ) async {
    final s = await signedInState(t);
    final clip = <String?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    await pumpApp(t, state: s, child: const KeychainScreen());
    await t.tap(find.byKey(const Key('key-password')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pw-name')), 'root pw');
    await t.enterText(find.byKey(const Key('pw-value')), 's3cret');
    await t.tap(find.byKey(const Key('pw-save')));
    await pumpReal(t, rounds: 10);
    final id = s.vault!.ofKind(ItemKind.identity).single.id;
    await t.tap(find.byKey(Key('identity-rename-$id')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('identity-name')), 'root password');
    await t.tap(find.byKey(const Key('identity-name-save')));
    await pumpReal(t, rounds: 10);
    expect(s.vault!.entry(id)!.name, 'root password');
    late IdentitySecret secret;
    await t.runAsync(() async => secret = (await s.vault!.identitySecret(id))!);
    expect(secret.password, 's3cret');
    // Passwords have no public key.
    expect(find.byKey(Key('identity-copy-$id')), findsNothing);
    expect(clip, isEmpty);
  });

  testWidgets(
    'an org vault lists the personal keys bound to its hosts, read-only; the personal vault does not',
    (t) async {
      final h = SyncHarness(capabilities: ['orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      final keys = FolderKeys.generate(1), f = newId();
      h.orgMembers[testOrgId] = {me};
      late String mine;
      await t.runAsync(() async {
        final pub = h.accounts.values.first.bundle.publicKey;
        final host = h.serverPutOrg(
          await sealOrgItem(
            keys,
            folderId: f,
            meta: {...hostJson('db'), 'identityMode': 'perMember'},
          ),
        );
        final folder = h.serverPutOrg(
          await sealOrgItem(keys, id: f, type: 'folder', meta: folderJson('P')),
        );
        h.orgBlock = orgBlock(
          members: [memberRow(me)],
          folderTree: [node(f)],
          acl: [
            aclRow(f, me, allow: ['view', 'connect']),
          ],
          wrappedKeys: [await wrappedRow(keys, f, pub)],
          itemIds: [host.id, folder.id],
        );
        await s.sync!.syncNow();
        mine = await s.vault!.upsertItem(
          type: 'identity',
          meta: IdentityMeta(
            name: 'atelier',
            kind: IdentityKind.password,
          ).toJson(),
          secret: IdentitySecret(
            kind: IdentityKind.password,
            password: 'x',
          ).toJson(),
        );
        await bindHost(s.vault!, host.id, mine);
      });
      s.orgs!.select(testOrgId);
      await pumpApp(t, state: s, child: const KeychainScreen());
      await pumpReal(t);
      expect(find.byKey(Key('identity-linked-$mine')), findsOneWidget);
      expect(find.byKey(Key('identity-rename-$mine')), findsNothing);
      s.orgs!.select(null);
      await t.pump();
      expect(find.byKey(Key('identity-linked-$mine')), findsNothing);
      expect(find.byKey(Key('identity-rename-$mine')), findsOneWidget);
    },
  );
}
