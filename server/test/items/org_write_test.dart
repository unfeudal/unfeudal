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
  setUp(() async {
    s = await TestServer.start(env: {'UNFEUDAL_MAX_ORG_SIZE': '16KB'});
    w = await OrgWorld.build(
      s,
      roles: {'adam': 'admin', 'ed': 'member', 'vic': 'member'},
      folders: {'prod': null, 'db': 'prod', 'ops': null},
    );
    await w.acl('prod', 'user:ed', allow: ['edit', 'connect']);
    await w.acl('prod', 'user:vic', allow: ['view', 'connect']);
  });
  tearDown(() => s.close());

  Map<String, Object?> keyId(
    Map<String, Object?> item,
    String part,
    String id,
  ) => {
    ...item,
    part: {...(item[part]! as Map<String, Object?>), 'keyId': id},
  };

  test(
    'edit is needed on the new and the old folder; root folders need an admin',
    () async {
      expect(
        (await w.put(
          w['vic'],
          await w.item(w['vic'], folder: 'prod'),
          0,
        )).status,
        403,
      );
      final host = await w.item(w['ed'], folder: 'prod');
      expect((await w.put(w['ed'], host, 0)).status, 200);
      final moved = await w.item(
        w['ed'],
        id: host['id']! as String,
        folder: 'ops',
      );
      expect(
        (await w.put(w['ed'], moved, 1)).status,
        403,
        reason: 'no edit on ops',
      );
      await w.acl('ops', 'user:vic', allow: ['edit']);
      final back = await w.item(
        w['vic'],
        id: host['id']! as String,
        folder: 'ops',
      );
      expect(
        (await w.put(w['vic'], back, 1)).status,
        403,
        reason: 'no edit on the old folder',
      );
      expect(
        (await w.put(w['ed'], await w.item(w['ed'], type: 'folder'), 0)).status,
        403,
        reason: 'root folder',
      );
      expect(
        (await w.put(
          w['adam'],
          await w.item(w['adam'], type: 'folder'),
          0,
        )).status,
        200,
      );
      expect(
        (await w.put(
          w['ed'],
          await w.item(w['ed'], type: 'folder', folder: 'prod'),
          0,
        )).status,
        200,
      );
    },
  );

  test('parents: a non-purged folder of this org, no cycle; other items need a folder', () async {
    // another org on the same database (a second TestServer would recreate the PostgreSQL schema)
    final beta = newId();
    await s.db.execute(
      "INSERT INTO orgs (id, name, settings, created_at) VALUES (@o, 'Beta', '{}', @t)",
      {'o': beta, 't': iso(s.clock.now())},
    );
    await s.db.execute(
      "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, 'owner', 'confirmed')",
      {'o': beta, 'u': w.id('olivia')},
    );
    final x = await testItem(
      w['olivia'],
      type: 'folder',
      scope: 'org',
      orgId: beta,
      meta: {'name': 'x'},
    );
    expect((await w.put(w['olivia'], x, 0)).status, 200);
    for (final parent in [newId(), x['id']! as String]) {
      final item = await testItemIn(w, parent);
      expect((await w.put(w['adam'], item, 0)).status, 400, reason: parent);
    }
    final host = await w.item(w['adam'], folder: 'prod');
    await w.put(w['adam'], host, 0);
    expect(
      (await w.put(
        w['adam'],
        await testItemIn(w, host['id']! as String),
        0,
      )).status,
      400,
      reason: 'a host is no folder',
    );
    await s.db.execute('UPDATE items SET purged = 1 WHERE id = @f', {
      'f': w.folder('ops'),
    });
    expect(
      (await w.put(
        w['adam'],
        await w.item(w['adam'], folder: 'ops'),
        0,
      )).status,
      400,
      reason: 'purged parent',
    );
    expect(
      (await w.put(w['adam'], {
        ...await w.item(w['adam'], folder: 'prod'),
        'folderId': null,
      }, 0)).status,
      400,
    );
    final prodUnderDb = await w.item(
      w['olivia'],
      id: w.folder('prod'),
      type: 'folder',
      folder: 'db',
    );
    expect(
      (await w.put(w['olivia'], prodUnderDb, 1)).status,
      400,
      reason: 'cycle',
    );
  });

  test('keyIds must name the folder at max(current, 1)', () async {
    final host = await w.item(w['ed'], folder: 'prod', secret: true);
    expect(
      (await w.put(
        w['ed'],
        keyId(host, 'meta', KeyIds.folder(w.folder('db'), 1, PayloadPart.meta)),
        0,
      )).status,
      400,
    );
    expect(
      (await w.put(
        w['ed'],
        keyId(
          host,
          'secret',
          KeyIds.folder(w.folder('prod'), 2, PayloadPart.secret),
        ),
        0,
      )).status,
      400,
    );
    expect(
      (await w.put(
        w['ed'],
        await w.item(w['ed'], folder: 'prod', keyVersion: 2),
        0,
      )).status,
      400,
    );
    await w.keys('prod', 3, ['olivia']);
    expect(
      (await w.put(w['ed'], host, 0)).status,
      400,
      reason: 'current is 3 now',
    );
    expect(
      (await w.put(
        w['ed'],
        await w.item(w['ed'], folder: 'prod', keyVersion: 3, secret: true),
        0,
      )).status,
      200,
    );
    final sub = await w.item(w['ed'], type: 'folder', folder: 'prod');
    expect(
      (await w.put(w['ed'], sub, 0)).status,
      200,
      reason: 'a new folder seals with its own v1',
    );
  });

  test('moving a folder: a gain the mover lacks is 403; lost readers are queued for rotation', () async {
    await w.keys('db', 1, ['olivia', 'vic']);
    await w.acl('ops', 'user:ed', allow: ['edit']);
    await w.acl('ops', 'user:vic', allow: ['view', 'connect', 'reveal']);
    final dbUnderOps = await w.item(
      w['ed'],
      id: w.folder('db'),
      type: 'folder',
      folder: 'ops',
    );
    expect(
      (await w.put(w['ed'], dbUnderOps, 1)).status,
      403,
      reason: 'vic would gain reveal on db, ed lacks it',
    );
    expect(await w.count('pending_rotations'), 0);
    await s.db.execute(
      'DELETE FROM acl_entries WHERE folder_id = @f AND principal_id = @u',
      {'f': w.folder('ops'), 'u': w.id('vic')},
    );
    expect(
      (await w.put(
        w['adam'],
        await w.item(
          w['adam'],
          id: w.folder('db'),
          type: 'folder',
          folder: 'ops',
        ),
        1,
      )).status,
      200,
    );
    final row = (await s.db.query(
      'SELECT folder_id, reason, removed_user_ids FROM pending_rotations',
    )).single;
    expect((row['folder_id'], row['reason']), (w.folder('db'), 'folder_moved'));
    // vic loses view; ed keeps view through edit but loses connect
    expect(
      jsonDecode(row['removed_user_ids']! as String),
      [w.id('vic'), w.id('ed')]..sort(),
    );
  });

  test('a non-member gets 404 without body for a tombstone or a type change; a member gets the tombstone', () async {
    final host = await w.item(w['ed'], folder: 'prod');
    await w.put(w['ed'], host, 0);
    await s.db.execute('UPDATE items SET purged = 1 WHERE id = @i', {
      'i': host['id'],
    });
    final out = await s.createUser('out@example.org');
    for (final probe in [
      host,
      {...host, 'type': 'snippet'},
    ]) {
      final r = await w.put(out, probe, 1);
      expect((r.status, r.body['item']), (404, null));
    }
    expect((await w.put(w['ed'], host, 1)).status, 409);
  });

  test('a key version change without the secret is 400 (check 7)', () async {
    final host = await w.item(w['ed'], folder: 'prod', secret: true);
    await w.put(w['ed'], host, 0);
    await w.keys('prod', 2, ['olivia']);
    final metaOnly = {
      ...await w.item(
        w['ed'],
        id: host['id']! as String,
        folder: 'prod',
        keyVersion: 2,
      ),
      'secret': null,
    };
    expect((await w.put(w['ed'], metaOnly, 1)).status, 400);
  });

  test(
    'content of a trashed folder: restore, move out or re-seal only',
    () async {
      final host = await w.item(w['ed'], folder: 'db');
      await w.put(w['ed'], host, 0);
      final db = await w.item(
        w['olivia'],
        id: w.folder('db'),
        type: 'folder',
        folder: 'prod',
        deleted: true,
      );
      expect((await w.put(w['olivia'], db, 1)).status, 200);
      final edit = await w.item(
        w['ed'],
        id: host['id']! as String,
        folder: 'db',
        deleted: true,
      );
      expect(
        (await w.put(w['ed'], edit, 1)).status,
        400,
        reason: 'deleted flag changed inside the trash',
      );
      final reseal = await w.item(
        w['ed'],
        id: host['id']! as String,
        folder: 'db',
      );
      expect((await w.put(w['ed'], reseal, 1)).status, 200);
      final out = await w.item(
        w['ed'],
        id: host['id']! as String,
        folder: 'prod',
      );
      expect((await w.put(w['ed'], out, 2)).status, 200);
    },
  );

  test('org_seq moves on folder create, move, delete, restore and on a folder change only', () async {
    Future<int> delta(Future<void> Function() write) async {
      final before = await w.orgSeq();
      await write();
      return await w.orgSeq() - before;
    }

    final f = await w.item(w['adam'], type: 'folder');
    expect(await delta(() async => w.put(w['adam'], f, 0)), 1);
    final fid = f['id']! as String;
    w.folders['f'] = fid;
    expect(
      await delta(
        () async => w.put(
          w['adam'],
          await w.item(w['adam'], id: fid, type: 'folder', folder: 'prod'),
          1,
        ),
      ),
      1,
    );
    expect(
      await delta(
        () async => w.put(
          w['adam'],
          await w.item(
            w['adam'],
            id: fid,
            type: 'folder',
            folder: 'prod',
            deleted: true,
          ),
          2,
        ),
      ),
      1,
    );
    expect(
      await delta(
        () async => w.put(
          w['adam'],
          await w.item(w['adam'], id: fid, type: 'folder', folder: 'prod'),
          3,
        ),
      ),
      1,
    );
    final host = await w.item(w['adam'], folder: 'prod');
    expect(await delta(() async => w.put(w['adam'], host, 0)), 0);
    expect(
      await delta(
        () async => w.put(
          w['adam'],
          await w.item(w['adam'], id: host['id']! as String, folder: 'prod'),
          1,
        ),
      ),
      0,
    );
    expect(
      await delta(
        () async => w.put(
          w['adam'],
          await w.item(w['adam'], id: host['id']! as String, folder: 'f'),
          2,
        ),
      ),
      1,
    );
  });

  test('a write over the org quota is 413', () async {
    final big = await w.item(w['adam'], folder: 'prod');
    final padded = {
      ...big,
      'meta': {...(big['meta']! as Map<String, Object?>), 'pad': 'x' * 17000},
    };
    final r = await w.put(w['adam'], padded, 0);
    expect((r.status, r.error), (413, 'payload_too_large'));
  });
}

/// A host whose folderId is [parent], sealed under [parent]'s keyId (so only the parent check can refuse it).
Future<Map<String, Object?>> testItemIn(OrgWorld w, String parent) async {
  final item = await w.item(w['adam'], folder: 'prod');
  return {
    ...item,
    'folderId': parent,
    'meta': {
      ...(item['meta']! as Map<String, Object?>),
      'keyId': KeyIds.folder(parent, 1, PayloadPart.meta),
    },
  };
}
