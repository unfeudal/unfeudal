// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/orgs/rotation_service.dart';
import 'package:unfeudal_client/src/vault/org_writer.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/sync_harness.dart';

void main() {
  late ClientOrg c;
  late RotationService rotation;
  late FolderKeys v1;
  late ({SimpleKeyPair pair, Uint8List publicKey}) mia;
  final f = newId(), miaId = newId(), kim = newId();
  late Item host;
  late OrgBlock block;
  setUp(() async {
    c = await ClientOrg.start();
    v1 = FolderKeys.generate(1);
    await c.keyring.put(f, v1);
    final k = mia = await memberKeys();
    await c.pins.pin(miaId, k.publicKey, verified: true);
    final folder = c.h.serverPutOrg(
      await sealOrgItem(v1, id: f, type: 'folder', meta: folderJson('Prod')),
    );
    host = c.h.serverPutOrg(
      await sealOrgItem(
        v1,
        folderId: f,
        meta: hostJson('db'),
        secret: {'note': 'x'},
      ),
    );
    block = orgBlock(
      role: 'admin',
      members: [
        c.me(),
        memberRow(miaId, status: 'confirmed', publicKey: k.publicKey),
        memberRow(
          kim,
          status: 'confirmed',
          publicKey: (await memberKeys()).publicKey,
        ),
      ],
      folderTree: [node(f)],
      acl: [
        aclRow(f, miaId, allow: ['view']),
      ],
      pendingRotations: [
        {
          'orgId': testOrgId,
          'folderId': f,
          'reason': 'member_removed',
          'removedUserIds': [kim],
          'rotatedVersion': null,
        },
      ],
      itemIds: [folder.id, host.id],
    );
    c.h.orgBlock = block;
    await c.sync.syncNow();
    await c.vault.reload();
    final writer = OrgWriter(
      vault: c.vault,
      mirror: c.mirror,
      keyring: c.keyring,
      api: c.api,
      block: () => block,
      userId: c.userId,
      publicKey: c.publicKey,
      online: () => true,
      emit: c.events.add,
    );
    rotation = RotationService(
      api: c.api,
      keyring: c.keyring,
      pins: c.pins,
      writer: writer,
      sync: c.sync,
      mirror: c.mirror,
      userId: c.userId,
      emit: c.events.add,
    );
  });

  group('a rotation after a removal', () {
    late Set<String> done;
    late Map<String, Object?> keysCall;
    setUp(() async {
      done = (await rotation.run(block)).done;
      keysCall = c.h.orgCalls
          .singleWhere((x) => x.route == 'PUT /folders/$f/keys')
          .body;
    });

    test('wraps version 2 keys for every reader but the removed one', () {
      final wraps = [
        for (final w in keysCall['wrapped']! as List)
          WrappedFolderKeys.fromJson(w),
      ];
      expect(keysCall['version'], 2);
      expect(wraps.map((w) => w.userId).toSet(), {c.userId, miaId});
      expect(
        wraps.firstWhere((w) => w.userId == miaId).secret,
        isNull,
        reason: 'mia has view only',
      );
    });

    test('seals the previous keys into the history', () async {
      final v2 = c.keyring.current(f)!;
      final history = FolderKeyHistory.fromJson(keysCall['history']);
      expect(
        b64((await history.open(v2, folderId: f)).single.metaKey),
        b64(v1.metaKey),
      );
    });

    test('re-seals the folder and its items under the new keys', () {
      expect(
        c.h.serverItem(host.id)!.meta!.keyId,
        KeyIds.folder(f, 2, PayloadPart.meta),
      );
      expect(
        c.h.serverItem(f)!.meta!.keyId,
        KeyIds.folder(f, 2, PayloadPart.meta),
      );
    });

    test('then reports the folder done and emits KeyRotated', () {
      expect(done, {f});
      expect(c.h.orgCalls.last.route, 'POST /folders/$f/rotation/done');
      expect(c.events.whereType<KeyRotated>(), hasLength(1));
    });
  });

  test(
    'a disabled reader gets no new keys and does not block the rotation',
    () async {
      final members = [
        c.me(),
        memberRow(
          miaId,
          status: 'confirmed',
          publicKey: mia.publicKey,
          disabled: true,
        ),
      ];
      final withDisabled = OrgBlock.fromJson({
        ...block.toJson(),
        'members': members,
      });
      expect((await rotation.run(withDisabled)).done, {f});
      final keysCall = c.h.orgCalls
          .singleWhere((x) => x.route == 'PUT /folders/$f/keys')
          .body;
      expect(
        [
          for (final w in keysCall['wrapped']! as List)
            WrappedFolderKeys.fromJson(w).userId,
        ],
        [c.userId],
      );
    },
  );

  test(
    'a removed member who reads the folder again gets the new keys',
    () async {
      await c.pins.pin(
        kim,
        block.members.firstWhere((m) => m.userId == kim).publicKey!,
        verified: true,
      );
      final reEnabled = OrgBlock.fromJson({
        ...block.toJson(),
        'acl': [
          ...block.toJson()['acl']! as List,
          aclRow(f, kim, allow: ['view']),
        ],
      });
      expect((await rotation.run(reEnabled)).done, {f});
      final keysCall = c.h.orgCalls
          .singleWhere((x) => x.route == 'PUT /folders/$f/keys')
          .body;
      expect(
        {
          for (final w in keysCall['wrapped']! as List)
            WrappedFolderKeys.fromJson(w).userId,
        },
        {c.userId, miaId, kim},
      );
    },
  );

  test(
    'after rotation the removed member\'s old keys open nothing new',
    () async {
      await rotation.run(block);
      final fresh = c.h.serverItem(host.id)!;
      await expectLater(
        PayloadCrypto.open(
          PayloadAad.of(fresh, PayloadPart.meta),
          fresh.meta!,
          v1.metaKey,
        ),
        throwsA(isA<DecryptionFailed>()),
      );
    },
  );

  test(
    'already rotated elsewhere: only re-seal leftovers and finish',
    () async {
      final v2 = FolderKeys.generate(2);
      await c.keyring.put(f, v2);
      final rotated = OrgBlock.fromJson({
        ...block.toJson(),
        'pendingRotations': [
          {
            'orgId': testOrgId,
            'folderId': f,
            'reason': 'member_removed',
            'removedUserIds': [kim],
            'rotatedVersion': 2,
          },
        ],
      });
      expect((await rotation.run(rotated)).done, {f});
      expect(
        c.h.orgCalls.where((x) => x.route == 'PUT /folders/$f/keys'),
        isEmpty,
      );
      expect(
        c.h.serverItem(host.id)!.meta!.keyId,
        KeyIds.folder(f, 2, PayloadPart.meta),
      );
    },
  );

  test('a reader this device has not pinned blocks the rotation; nothing is pinned or uploaded', () async {
    final ana = newId(), json = block.toJson();
    final withAna = OrgBlock.fromJson({
      ...json,
      'members': [
        ...json['members']! as List,
        memberRow(
          ana,
          status: 'confirmed',
          publicKey: (await memberKeys()).publicKey,
        ),
      ],
      'acl': [
        ...json['acl']! as List,
        aclRow(f, ana, allow: ['view']),
      ],
    });
    final report = await rotation.run(withAna);
    expect(report.done, isEmpty);
    expect(report.blocked, {ana});
    expect(c.pins.pinOf(ana), isNull);
    expect(c.h.orgCalls, isEmpty);
  });

  test(
    'a folder blocked by an unpinned reader does not stop the next folder',
    () async {
      final ana = newId(), g = newId(), json = block.toJson();
      await c.keyring.put(g, v1);
      final second = c.h.serverPutOrg(
        await sealOrgItem(v1, id: g, type: 'folder', meta: folderJson('Dev')),
      );
      final twoFolders = OrgBlock.fromJson({
        ...json,
        'members': [
          ...json['members']! as List,
          memberRow(
            ana,
            status: 'confirmed',
            publicKey: (await memberKeys()).publicKey,
          ),
        ],
        'folderTree': [node(f), node(g)],
        'acl': [
          ...json['acl']! as List,
          aclRow(f, ana, allow: ['view']),
        ],
        'pendingRotations': [
          ...json['pendingRotations']! as List,
          {
            'orgId': testOrgId,
            'folderId': g,
            'reason': 'member_removed',
            'removedUserIds': [kim],
            'rotatedVersion': null,
          },
        ],
        'itemIds': [...json['itemIds']! as List, second.id],
      });
      block = c.h.orgBlock = twoFolders;
      final report = await rotation.run(twoFolders);
      expect(report.done, {g});
      expect(report.blocked, {ana});
    },
  );

  test(
    'a 409 on rotation/done leaves the rotation pending; a member does nothing',
    () async {
      c.h.orgReplies['POST /folders/$f/rotation/done'] = (_) =>
          SyncHarness.reply({'error': 'conflict', 'message': ''}, 409);
      expect((await rotation.run(block)).done, isEmpty);
      final asMember = OrgBlock.fromJson({
        ...block.toJson(),
        'orgs': [
          {
            'id': testOrgId,
            'name': 'Acme',
            'role': 'member',
            'status': 'confirmed',
            'settings': {'mascot': true},
          },
        ],
      });
      c.h.orgCalls.clear();
      await rotation.run(asMember);
      expect(c.h.orgCalls, isEmpty);
    },
  );
}
