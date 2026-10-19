// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/orgs/block_permissions.dart';
import 'package:unfeudal_client/src/vault/org_writer.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';

void main() {
  late ClientOrg c;
  late OrgWriter writer;
  late OrgBlock block;
  final f = newId(), g = newId();
  setUp(() async {
    c = await ClientOrg.start();
    await c.keyring.put(f, FolderKeys.generate(1));
    await c.keyring.put(g, FolderKeys.generate(1));
    block = orgBlock(
      role: 'member',
      members: [c.me(role: 'member')],
      folderTree: [node(f), node(g)],
      acl: [
        aclRow(f, c.userId, allow: ['edit', 'connect']),
        aclRow(g, c.userId, allow: ['view']),
      ],
    );
    writer = OrgWriter(
      vault: c.vault,
      mirror: c.mirror,
      keyring: c.keyring,
      api: c.api,
      block: () => block,
      userId: c.userId,
      publicKey: c.publicKey,
      write: c.write,
      online: () => !c.h.offline,
      emit: c.events.add,
    );
  });

  Future<Item> queued(String id) async =>
      c.mirror.outbox().singleWhere((e) => e.item.id == id).item;

  test('writes into a folder with edit, sealed with its keys at the current version, offline too', () async {
    c.h.offline = true;
    final id = await writer.upsert(
      type: 'host',
      target: OrgTarget(testOrgId, f),
      meta: hostJson('db'),
    );
    final item = await queued(id);
    expect(
      (item.scope, item.orgId, item.folderId, item.meta!.keyId),
      (ItemScope.org, testOrgId, f, KeyIds.folder(f, 1, PayloadPart.meta)),
    );
    await c.vault.reload();
    expect(c.vault.entry(id)!.name, 'db');
  });

  test(
    'refused without edit in the cached block; folders need the server',
    () async {
      await expectLater(
        writer.upsert(
          type: 'host',
          target: OrgTarget(testOrgId, g),
          meta: hostJson('x'),
        ),
        throwsA(
          isA<OrgWriteRefused>().having(
            (e) => e.reason,
            'reason',
            OrgWriteRefusal.noEdit,
          ),
        ),
      );
      c.h.offline = true;
      await expectLater(
        writer.createFolder(
          orgId: testOrgId,
          parentId: f,
          meta: FolderMeta.fromJson(folderJson('sub')),
        ),
        throwsA(
          isA<OrgWriteRefused>().having(
            (e) => e.reason,
            'reason',
            OrgWriteRefusal.needsServer,
          ),
        ),
      );
      expect(c.mirror.outbox(), isEmpty);
    },
  );

  test('a move needs edit on both folders and re-seals both parts with the new folder keys', () async {
    final id = await writer.upsert(
      type: 'identity',
      target: OrgTarget(testOrgId, f),
      meta: {
        'schemaVersion': 1,
        'name': 'deploy',
        'kind': 'password',
        'publicKey': null,
      },
      secret: {
        'schemaVersion': 1,
        'kind': 'password',
        'privateKeyPem': null,
        'passphrase': null,
        'password': 'pw',
      },
    );
    confirmOutbox(c.mirror);
    await c.vault.reload();
    await expectLater(
      writer.upsert(
        type: 'identity',
        id: id,
        target: OrgTarget(testOrgId, g),
        meta: c.vault.entry(id)!.meta!,
      ),
      throwsA(isA<OrgWriteRefused>()),
    );
    block = orgBlock(
      role: 'member',
      members: [c.me(role: 'member')],
      folderTree: [node(f), node(g)],
      acl: [
        aclRow(f, c.userId, allow: ['edit', 'connect']),
        aclRow(g, c.userId, allow: ['edit', 'connect']),
      ],
    );
    await writer.upsert(
      type: 'identity',
      id: id,
      target: OrgTarget(testOrgId, g),
      meta: c.vault.entry(id)!.meta!,
    );
    final moved = await queued(id);
    expect(
      (moved.folderId, moved.secret!.keyId),
      (g, KeyIds.folder(g, 1, PayloadPart.secret)),
    );
  });

  test('a secret needs the secret key (connect)', () async {
    await c.keyring.put(f, FolderKeys(2, FolderKeys.generate(2).metaKey, null));
    await expectLater(
      writer.upsert(
        type: 'identity',
        target: OrgTarget(testOrgId, f),
        meta: {
          'schemaVersion': 1,
          'name': 'k',
          'kind': 'password',
          'publicKey': null,
        },
        secret: {
          'schemaVersion': 1,
          'kind': 'password',
          'privateKeyPem': null,
          'passphrase': null,
          'password': 'pw',
        },
      ),
      throwsA(
        isA<OrgWriteRefused>().having(
          (e) => e.reason,
          'reason',
          OrgWriteRefusal.noSecretKey,
        ),
      ),
    );
  });

  test('createFolder online: item first, then the first keys for the creator; root needs an admin', () async {
    await expectLater(
      writer.createFolder(
        orgId: testOrgId,
        parentId: null,
        meta: FolderMeta.fromJson(folderJson('root')),
      ),
      throwsA(
        isA<OrgWriteRefused>().having(
          (e) => e.reason,
          'reason',
          OrgWriteRefusal.noEdit,
        ),
      ),
    );
    final id = await writer.createFolder(
      orgId: testOrgId,
      parentId: f,
      meta: FolderMeta.fromJson(folderJson('sub')),
    );
    expect(
      c.h.serverItem(id)!.meta!.keyId,
      KeyIds.folder(id, 1, PayloadPart.meta),
    );
    final keysCall = c.h.orgCalls
        .singleWhere((x) => x.route == 'PUT /folders/$id/keys')
        .body;
    final wrap = WrappedFolderKeys.fromJson(
      (keysCall['wrapped']! as List).single,
    );
    expect((keysCall['version'], wrap.userId), (1, c.userId));
    expect(
      b64((await wrap.unwrap(id, c.keyPair)).metaKey),
      b64(c.keyring.current(id)!.metaKey),
    );
    expect(c.events.whereType<SharedVaultCreated>().single.orgId, testOrgId);
  });

  test('trash, restore and a conflict copy stay in the org folder', () async {
    final id = await writer.upsert(
      type: 'host',
      target: OrgTarget(testOrgId, f),
      meta: hostJson('db'),
    );
    confirmOutbox(c.mirror);
    await c.vault.reload();
    await writer.trash(id);
    expect((await queued(id)).deleted, isTrue);
    confirmOutbox(c.mirror);
    await c.vault.reload();
    await writer.restore(id);
    expect((await queued(id)).deleted, isFalse);
    final copy = (await writer.conflictCopy(
      c.mirror.item(id)!,
      suffix: ' (copy)',
    ))!;
    expect(
      (copy.scope, copy.folderId, copy.id == id, copy.revision),
      (ItemScope.org, f, false, 0),
    );
    expect(
      explainFromBlock(block, testOrgId, c.userId, f).effective,
      contains(Permission.edit),
    );
  });
}
