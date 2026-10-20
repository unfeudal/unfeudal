// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/orgs/folder_keyring.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';

void main() {
  final userKey = Uint8List.fromList(List.filled(32, 2));
  late LocalMirror m;
  late Vault v;
  late FolderKeyring ring;
  final f = newId();
  late FolderKeys keys;
  setUp(() async {
    m = LocalMirror.inMemory();
    v = await testVault(userKey, m);
    ring = FolderKeyring(m);
    await ring.load(userKey);
    keys = FolderKeys.generate(1);
    await ring.put(f, keys);
  });

  test('org items open with the keyring and carry their org id', () async {
    final folder = await sealOrgItem(
      keys,
      id: f,
      type: 'folder',
      meta: folderJson('Prod'),
    );
    final host = await sealOrgItem(keys, folderId: f, meta: hostJson('db'));
    m.upsertItems([folder, host]);
    await v.reload();
    expect(
      v.entry(host.id),
      isNull,
      reason: 'no keyring yet: org items stay hidden',
    );
    v.keyring = ring;
    await v.reload();
    expect(
      (
        v.entry(host.id)!.state,
        v.entry(host.id)!.orgId,
        v.entry(host.id)!.name,
      ),
      (EntryState.ok, testOrgId, 'db'),
    );
    expect(v.hostLookup(host.id)!.resolved.port, 22);
  });

  test(
    'without the folder key an org item is unreadable and awaiting a key',
    () async {
      final other = newId();
      m.upsertItems([
        await sealOrgItem(
          FolderKeys.generate(1),
          folderId: other,
          meta: hostJson('x'),
        ),
      ]);
      v.keyring = ring;
      await v.reload();
      final e = v.entries.single;
      expect((e.state, e.awaitingKey), (EntryState.unreadable, true));
    },
  );

  test('a payload sealed under another folder\'s key is refused', () async {
    final g = newId();
    await ring.put(g, keys);
    final foreign = await sealOrgItem(
      keys,
      folderId: g,
      meta: hostJson('moved'),
    );
    final relabelled = Item.fromJson({...foreign.toJson(), 'folderId': f});
    m.upsertItems([relabelled]);
    v.keyring = ring;
    await v.reload();
    expect(
      (v.entries.single.state, v.entries.single.awaitingKey),
      (EntryState.unreadable, false),
    );
  });

  test('a replayed org payload is ignored like a personal one', () async {
    v.keyring = ring;
    final id = newId();
    m.upsertItems([
      await sealOrgItem(
        keys,
        id: id,
        folderId: f,
        meta: hostJson('v2'),
        seq: 2,
        revision: 2,
      ),
    ]);
    await v.reload();
    m.upsertItems([
      await sealOrgItem(
        keys,
        id: id,
        folderId: f,
        meta: hostJson('v1'),
        revision: 3,
      ),
    ]);
    await v.reload();
    expect(v.entry(id)!.name, 'v2');
  });

  test('personal writers refuse org entries', () async {
    v.keyring = ring;
    final host = await sealOrgItem(keys, folderId: f, meta: hostJson('db'));
    m.upsertItems([host]);
    await v.reload();
    await expectLater(
      v.upsertItem(type: 'host', id: host.id, meta: hostJson('x')),
      throwsStateError,
    );
    await expectLater(v.trashItem(host.id), throwsStateError);
  });
}
