// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/items.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  late Map<String, String> items; // name to id
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {
        'adam': 'admin',
        'mia': 'member',
        'vic': 'member',
        'ana': 'member',
        'dis': 'member',
      },
      accepted: {'ana'},
      teams: {
        'Ops': ['mia'],
        'Dev': ['vic'],
      },
      folders: {'prod': null, 'db': 'prod', 'web': 'prod', 'hr': null},
    );
    await w.acl('db', 'team:Ops', allow: ['connect']);
    await w.acl('web', 'user:vic', allow: ['view']);
    await w.acl('hr', 'team:Dev', allow: ['view']);
    await w.acl('hr', 'user:vic', deny: ['view']);
    await w.acl('db', 'user:dis', allow: ['view']);
    items = {};
    for (final f in ['prod', 'db', 'web', 'hr']) {
      final host = await w.item(w['olivia'], folder: f, secret: true);
      expect((await w.put(w['olivia'], host, 0)).status, 200);
      items[f] = host['id']! as String;
    }
    await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
      'u': w.id('dis'),
    });
  });
  tearDown(() => s.close());

  Set<String> ids(SyncPage p) => p.items.map((i) => i.id).toSet();

  test('a member gets the items of viewable folders and the folder items of their tree', () async {
    final page = await w.sync(w['mia']);
    expect(ids(page), {items['db'], w.folder('db'), w.folder('prod')});
    expect(page.org!.itemIds, (ids(page).toList()..sort()));
    expect(ids(await w.sync(w['vic'])), {
      items['web'],
      w.folder('web'),
      w.folder('prod'),
    }, reason: 'hr denied');
    expect(ids(await w.sync(w['adam'])), {
      ...items.values,
      ...w.folders.values,
    });
  });

  test(
    'trash and tombstones of viewable folders are sent; purged folders are not',
    () async {
      // a real trash write: the page serves the stored body, not the column
      final trashed = await w.item(
        w['olivia'],
        id: items['db'],
        folder: 'db',
        secret: true,
        deleted: true,
      );
      expect((await w.put(w['olivia'], trashed, 1)).status, 200);
      final page = await w.sync(w['mia']);
      expect(page.items.firstWhere((i) => i.id == items['db']).deleted, isTrue);
      await s.db.execute('UPDATE items SET purged = 1 WHERE id IN (@a, @b)', {
        'a': items['db'],
        'b': w.folder('web'),
      });
      expect(ids(await w.sync(w['mia'])), contains(items['db']));
      expect(ids(await w.sync(w['vic'])), isNot(contains(w.folder('web'))));
    },
  );

  test('an accepted member sees the org name only; a disabled or removed one gets nothing', () async {
    final page = await w.sync(w['ana']);
    expect(page.items, isEmpty);
    final b = page.org!;
    expect(b.orgs.single.status, 'accepted');
    expect([
      b.members,
      b.teams,
      b.acl,
      b.folderTree,
      b.wrappedKeys,
      b.keyHistory,
      b.keyRequests,
      b.pendingRotations,
      b.itemIds,
    ], everyElement(isEmpty));
    await w.keys('db', 1, ['mia']);
    await s.delete(
      '/api/v1/orgs/${w.orgId}/members/${w.id('mia')}',
      token: w['adam'].accessToken,
    );
    final gone = await w.sync(w['mia']);
    expect(gone.items, isEmpty);
    expect(gone.org!.orgs, isEmpty);
    expect(gone.org!.wrappedKeys, isEmpty);
  });

  test('being Instance Owner gives nothing in an org', () async {
    final page = await w.sync(w.io);
    expect(ids(page), isEmpty);
    expect(page.org!.orgs, isEmpty);
  });

  group('a member', () {
    late OrgBlock b;
    setUp(() async {
      await w.keys('db', 1, ['mia', 'olivia']);
      await w.keys('hr', 1, ['vic']);
      b = await w.block(w['mia']);
    });

    test('sees their teams, the ACLs and the folder tree of their tree', () {
      expect(b.teams.map((t) => t.name), ['Ops']);
      expect(b.acl.map((a) => a.folderId).toSet(), {w.folder('db')});
      expect(b.folderTree.map((n) => (n.folderId, n.parentId)).toSet(), {
        (w.folder('db'), w.folder('prod')),
        (w.folder('prod'), null),
      });
    });

    test('sees every member without status, public key or disabled', () {
      expect(
        b.members.every(
          (m) => m.status == null && m.publicKey == null && m.disabled == null,
        ),
        isTrue,
      );
      expect(
        b.members.map((m) => m.email).toSet(),
        containsAll(['dis@example.org', 'ana@example.org']),
      );
    });

    test('gets only their own wraps, no key requests or rotations', () async {
      expect(b.wrappedKeys.map((k) => k.folderId), [w.folder('db')]);
      expect(b.keyRequests, isEmpty);
      expect(b.pendingRotations, isEmpty);
      expect(
        (await w.block(w['vic'])).wrappedKeys,
        isEmpty,
        reason: 'hr is denied now',
      );
    });
  });

  test('admins see statuses, public keys, every team and ACL, key requests and pending rotations', () async {
    await w.keys('db', 1, ['olivia', 'adam']);
    await w.keys('prod', 1, ['olivia']);
    await s.db.execute(
      "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES (@o, @f, 'acl_change', @r)",
      {
        'o': w.orgId,
        'f': w.folder('db'),
        'r': jsonEncode([w.id('vic')]),
      },
    );
    final b = await w.block(w['adam']);
    final mia = b.members.firstWhere((m) => m.userId == w.id('mia'));
    expect(
      (mia.status, b64(mia.publicKey!), mia.disabled),
      ('confirmed', b64(w['mia'].bundle.publicKey), false),
    );
    expect(
      b.members.firstWhere((m) => m.userId == w.id('dis')).disabled,
      isTrue,
    );
    expect((b.teams.length, b.acl.length, b.folderTree.length), (2, 5, 4));
    expect(
      b.keyRequests
          .map((r) => (r.folderId, r.userId, r.version, r.secret))
          .toSet(),
      {
        (w.folder('db'), w.id('mia'), 1, true),
        (w.folder('prod'), w.id('adam'), 1, true),
      },
      reason: 'dis is disabled; folders at version 0 ask nothing; vic sees prod only through web',
    );
    expect(b.pendingRotations.single.removedUserIds, [w.id('vic')]);
    await w.keys('db', 1, ['mia'], metaOnly: {'mia'});
    expect(
      (await w.block(w['adam'])).keyRequests
          .where((r) => r.userId == w.id('mia'))
          .single
          .secret,
      isTrue,
      reason: 'connect without a secret wrap',
    );
  });

  test('keyHistory: viewable folders; secret only with connect', () async {
    await s.db.execute(
      'INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES (@o, @f, 2, @b)',
      {
        'o': w.orgId,
        'f': w.folder('web'),
        'b': jsonEncode({
          'version': 2,
          'meta': OrgWorld.sealed(w.folder('web'), 2, 'meta'),
          'secret': OrgWorld.sealed(w.folder('web'), 2, 'secret'),
        }),
      },
    );
    final vic = await w.block(w['vic']);
    expect(vic.keyHistory.single.folderId, w.folder('web'));
    expect(vic.keyHistory.single.keys.secret, isNull);
    expect((await w.block(w['adam'])).keyHistory.single.keys.secret, isNotNull);
    expect((await w.block(w['mia'])).keyHistory, isEmpty);
  });

  group('block rows keep their wire keys in order', () {
    setUp(() async {
      await w.keys('db', 1, ['olivia', 'adam']);
      await w.keys('prod', 1, ['olivia']);
      await s.db.execute(
        "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES (@o, @f, 'acl_change', @r)",
        {
          'o': w.orgId,
          'f': w.folder('db'),
          'r': jsonEncode([w.id('vic')]),
        },
      );
      await s.db.execute(
        'INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES (@o, @f, 2, @b)',
        {
          'o': w.orgId,
          'f': w.folder('web'),
          'b': jsonEncode({
            'version': 2,
            'meta': OrgWorld.sealed(w.folder('web'), 2, 'meta'),
            'secret': OrgWorld.sealed(w.folder('web'), 2, 'secret'),
          }),
        },
      );
    });
    Future<Map<String, Object?>> raw(String name) async =>
        (await s.get(
              '/api/v1/sync?cursor=0&orgCursor=0',
              token: w[name].accessToken,
            )).body['org']!
            as Map<String, Object?>;
    List<Map<String, Object?>> rows(Map<String, Object?> block, String key) =>
        (block[key]! as List).cast<Map<String, Object?>>();

    test('top level, orgs and members, for an admin', () async {
      final admin = await raw('adam');
      expect(admin.keys, [
        'orgCursor',
        'orgs',
        'members',
        'teams',
        'acl',
        'folderTree',
        'wrappedKeys',
        'keyHistory',
        'keyRequests',
        'pendingRotations',
        'itemIds',
      ]);
      expect(rows(admin, 'orgs').single.keys, [
        'id',
        'name',
        'role',
        'status',
        'settings',
      ]);
      expect(
        rows(
          admin,
          'members',
        ).firstWhere((m) => m['userId'] == w.id('mia')).keys,
        ['orgId', 'userId', 'email', 'role', 'status', 'publicKey', 'disabled'],
      );
    });

    test('teams, ACL entries and folder tree, nulls included', () async {
      final admin = await raw('adam');
      expect(rows(admin, 'teams').first.keys, [
        'orgId',
        'id',
        'name',
        'memberIds',
      ]);
      expect(rows(admin, 'acl').first.keys, [
        'orgId',
        'folderId',
        'principalType',
        'principalId',
        'allow',
        'deny',
      ]);
      expect(
        rows(
          admin,
          'folderTree',
        ).firstWhere((n) => n['folderId'] == w.folder('prod')),
        {'orgId': w.orgId, 'folderId': w.folder('prod'), 'parentId': null},
      );
    });

    test('wraps, key requests and pending rotations, nulls included', () async {
      final admin = await raw('adam');
      expect(rows(admin, 'wrappedKeys').single.keys, [
        'folderId',
        'version',
        'meta',
        'secret',
      ]);
      expect(rows(admin, 'keyRequests').first.keys, [
        'orgId',
        'folderId',
        'userId',
        'version',
        'secret',
      ]);
      final rotation = rows(admin, 'pendingRotations').single;
      expect(rotation.keys, [
        'orgId',
        'folderId',
        'reason',
        'removedUserIds',
        'rotatedVersion',
      ]);
      expect(rotation['rotatedVersion'], isNull);
    });

    test(
      'a member gets no admin fields; key history keeps its null secret',
      () async {
        expect(
          rows(await raw('mia'), 'members').map((m) => m.keys),
          everyElement(['orgId', 'userId', 'email', 'role']),
        );
        final history = rows(await raw('vic'), 'keyHistory').single;
        expect(history.keys, ['folderId', 'version', 'meta', 'secret']);
        expect(history['secret'], isNull);
      },
    );
  });

  test('the block comes only when org_seq passed orgCursor; settings carry mascot only', () async {
    final first = await w.sync(w['mia']);
    final seq = first.org!.orgCursor;
    expect(seq, await w.orgSeq());
    expect((await w.sync(w['mia'], orgCursor: seq)).org, isNull);
    await s.put(
      '/api/v1/orgs/${w.orgId}',
      token: w['olivia'].accessToken,
      body: {
        'settings': {'mascot': false},
      },
    );
    final org = (await w.sync(w['mia'], orgCursor: seq)).org!;
    expect(org.orgs.single.mascot, false);
    expect(org.orgs.single.settings.keys.toSet(), {'mascot'});
  });

  test('personal and org items share one page in seq order', () async {
    final mine = await testItem(w['mia']);
    await s.put(
      '/api/v1/items/${mine['id']}',
      token: w['mia'].accessToken,
      body: mine,
      headers: {'if-match': '0'},
    );
    final later = await w.item(w['olivia'], folder: 'db');
    await w.put(w['olivia'], later, 0);
    final page = await w.sync(w['mia']);
    final seqs = {
      for (final r in await s.db.query('SELECT id, seq FROM items'))
        r['id']: r['seq']! as int,
    };
    final order = page.items.map((i) => seqs[i.id]!).toList();
    expect(order, [...order]..sort());
    expect(
      page.items.map((i) => i.id).toList().sublist(page.items.length - 2),
      [mine['id'], later['id']],
    );
    expect(page.cursor, order.last);
    final next = await w.sync(
      w['mia'],
      cursor: page.cursor,
      orgCursor: page.org!.orgCursor,
    );
    expect(next.items, isEmpty);
    expect(next.org, isNull);
  });

  test('orgs off: no org item and no block', () async {
    final off = await TestServer.start(env: {'UNFEUDAL_FEATURE_ORGS': 'false'});
    addTearDown(off.close);
    final o = await OrgWorld.build(off);
    final r = await off.get('/api/v1/sync', token: o['olivia'].accessToken);
    expect(r.body['items'], isEmpty);
    expect(r.body.containsKey('org'), isFalse);
  });
}
