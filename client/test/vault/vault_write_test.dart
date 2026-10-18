// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  final key = SymmetricCipher.newKey();
  const pem =
      '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----';
  Map<String, Object?> idMeta(String name) => {
    'schemaVersion': 1,
    'name': name,
    'kind': 'privateKey',
    'publicKey': null,
  };
  final idSecret = {
    'schemaVersion': 1,
    'kind': 'privateKey',
    'privateKeyPem': pem,
    'passphrase': null,
    'password': null,
  };

  test(
    'a new item is personal, keyId user, meta and secret share one seq',
    () async {
      final m = LocalMirror.inMemory();
      final v = await testVault(key, m);
      final id = await v.upsertItem(
        type: 'identity',
        meta: idMeta('deploy'),
        secret: idSecret,
      );
      final sent = m.outbox().single;
      expect(
        (
          sent.item.scope,
          sent.item.meta!.keyId,
          sent.item.secret!.keyId,
          sent.baseRevision,
        ),
        (ItemScope.personal, 'user', 'user', 0),
      );
      final meta = await PayloadCrypto.open(
        PayloadAad.of(sent.item, PayloadPart.meta),
        sent.item.meta!,
        key,
      );
      final secret = await PayloadCrypto.open(
        PayloadAad.of(sent.item, PayloadPart.secret),
        sent.item.secret!,
        key,
      );
      expect((meta.seq, secret.seq), (1, 1));
      expect(v.entry(id)!.pending, isTrue);
    },
  );

  test(
    'an edit in place keeps the stored secret (null); a move re-seals it',
    () async {
      final m = LocalMirror.inMemory();
      final a = newId(), b = newId();
      m.upsertItems([
        await sealItem(key, id: a, type: 'folder', meta: folderJson('A')),
        await sealItem(key, id: b, type: 'folder', meta: folderJson('B')),
      ]);
      final ident = await sealItem(
        key,
        type: 'identity',
        folderId: a,
        meta: idMeta('k'),
        secret: idSecret,
        seq: 3,
        revision: 4,
      );
      m.upsertItems([ident]);
      final v = await testVault(key, m);
      await v.updateIdentity(
        ident.id,
        IdentityMeta.fromJson(idMeta('renamed')),
      );
      expect(m.outbox().single.item.secret, isNull);
      await v.upsertItem(
        id: ident.id,
        type: 'identity',
        folderId: b,
        meta: idMeta('renamed'),
      );
      final moved = m.outbox().single;
      expect((moved.item.folderId, moved.baseRevision), (b, 4));
      final secret = await PayloadCrypto.open(
        PayloadAad.of(moved.item, PayloadPart.secret),
        moved.item.secret!,
        key,
      );
      expect(secret.json['privateKeyPem'], pem);
      expect(
        secret.seq,
        5,
      ); // above the mark of 3 and the in-place edit (4) of this session
    },
  );

  test(
    'read-only, unreadable and unsupported entries are never rewritten',
    () async {
      final m = LocalMirror.inMemory();
      final newer = await sealItem(
        key,
        meta: {...hostJson('n'), 'schemaVersion': 2},
      );
      final bad = await sealItem(SymmetricCipher.newKey(), meta: hostJson('x'));
      m.upsertItems([newer, bad]);
      final v = await testVault(key, m);
      for (final id in [newer.id, bad.id]) {
        await expectLater(
          v.upsertItem(id: id, type: 'host', meta: hostJson('y')),
          throwsStateError,
        );
        await expectLater(v.trashItem(id), throwsStateError);
      }
      expect(m.outbox(), isEmpty);
    },
  );

  test(
    'trash and restore; a trashed folder trashes its subtree; no folder cycle',
    () async {
      final m = LocalMirror.inMemory();
      final v = await testVault(key, m);
      final top = await v.saveFolder(FolderMeta.fromJson(folderJson('top')));
      final sub = await v.saveFolder(
        FolderMeta.fromJson(folderJson('sub')),
        parentId: top,
      );
      final host = await v.upsertItem(
        type: 'host',
        folderId: sub,
        meta: hostJson('web'),
      );
      await expectLater(
        v.saveFolder(
          FolderMeta.fromJson(folderJson('top')),
          id: top,
          parentId: sub,
        ),
        throwsArgumentError,
      );
      await v.deleteFolder(top);
      expect(
        (v.isTrashed(top), v.isTrashed(sub), v.isTrashed(host)),
        (true, true, true),
      );
      expect(v.ofKind(ItemKind.host), isEmpty);
      await v.restoreItem(top);
      expect(v.ofKind(ItemKind.host).single.id, host);
      await v.trashItem(host);
      expect(
        m.outbox().firstWhere((e) => e.item.id == host).item.deleted,
        isTrue,
      );
    },
  );

  test('identity kinds must match; the secret opens back', () async {
    final m = LocalMirror.inMemory();
    final v = await testVault(key, m);
    final id = await v.upsertItem(
      type: 'identity',
      meta: idMeta('k'),
      secret: idSecret,
    );
    expect((await v.identitySecret(id))!.privateKeyPem, pem);
    final pw = IdentitySecret.fromJson({
      'schemaVersion': 1,
      'kind': 'password',
      'privateKeyPem': null,
      'passphrase': null,
      'password': 'p',
    });
    await expectLater(
      v.updateIdentity(id, IdentityMeta.fromJson(idMeta('k')), secret: pw),
      throwsArgumentError,
    );
  });

  test(
    'profile: smallest id wins; prefs merge, keep unknown keys, null removes',
    () async {
      final m = LocalMirror.inMemory();
      final low = '00000000-0000-4000-8000-000000000001',
          high = 'ffffffff-ffff-4fff-bfff-ffffffffffff';
      m.upsertItems([
        await sealItem(
          key,
          id: high,
          type: 'profile',
          meta: {
            'schemaVersion': 1,
            'displayName': 'Late',
            'prefs': {'themeMode': 'light'},
          },
        ),
        await sealItem(
          key,
          id: low,
          type: 'profile',
          meta: {
            'schemaVersion': 1,
            'displayName': 'Camille',
            'prefs': {'themeMode': 'dark', 'future': 1},
          },
        ),
      ]);
      final v = await testVault(key, m);
      expect(
        (v.profile.displayName, v.profile.prefs['themeMode']),
        ('Camille', 'dark'),
      );
      await v.setPrefs({'themeMode': null, 'locale': 'fr'});
      final sent = m.outbox().single.item;
      expect(sent.id, low);
      expect(
        (await v.open(
          sent,
          PayloadPart.meta,
          fromServer: false,
        ))!.json['prefs'],
        {'future': 1, 'locale': 'fr'},
      );
    },
  );

  test(
    'conflict copy: new id, revision 0, suffixed name, secret re-sealed',
    () async {
      final m = LocalMirror.inMemory();
      final v = await testVault(key, m);
      final id = await v.upsertItem(
        type: 'identity',
        meta: idMeta('deploy'),
        secret: idSecret,
      );
      final mine = m.outbox().single.item;
      final copy = (await v.conflictCopy(mine, suffix: ' (conflict copy)'))!;
      expect(
        (copy.id == id, copy.revision ?? 0, copy.type),
        (false, 0, 'identity'),
      );
      expect(
        (await v.open(copy, PayloadPart.meta, fromServer: false))!.json['name'],
        'deploy (conflict copy)',
      );
      expect(
        (await v.open(
          copy,
          PayloadPart.secret,
          fromServer: false,
        ))!.json['privateKeyPem'],
        pem,
      );
    },
  );

  test('resolve: inherited values and their source', () async {
    final m = LocalMirror.inMemory();
    final v = await testVault(key, m);
    final top = await v.saveFolder(
      FolderMeta.fromJson(folderJson('top', port: 2222, user: 'ops')),
    );
    final sub = await v.saveFolder(
      FolderMeta.fromJson(folderJson('sub', user: 'deploy')),
      parentId: top,
    );
    final host = await v.upsertItem(
      type: 'host',
      folderId: sub,
      meta: hostJson('web'),
    );
    final r = v.resolve(host);
    expect((r.port, r.user, r.identityId), (2222, 'deploy', null));
    expect(r.sources, {
      'port': top,
      'user': sub,
      'identityId': 'default',
      'jumpHostId': 'default',
    });
    expect(v.hostLookup(host)!.meta.name, 'web');
  });

  test(
    'editing an item whose create is still queued keeps its secret',
    () async {
      final m = LocalMirror.inMemory();
      final v = await testVault(key, m);
      final id = await v.upsertItem(
        type: 'identity',
        meta: idMeta('deploy'),
        secret: idSecret,
      );
      await v.updateIdentity(
        id,
        IdentityMeta.fromJson(idMeta('renamed')),
      ); // before the create reached the server
      final queued = m.outbox().single.item;
      expect(queued.secret, isNotNull);
      final secret = await PayloadCrypto.open(
        PayloadAad.of(queued, PayloadPart.secret),
        queued.secret!,
        key,
      );
      expect(secret.json['privateKeyPem'], pem);
      await v.trashItem(id);
      expect(m.outbox().single.item.secret, isNotNull);
    },
  );
}
