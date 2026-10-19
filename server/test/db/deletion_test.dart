// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/deletion.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/items.dart';
import '../support/matchers.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'mia': 'member', 'max': 'member', 'oscar': 'owner'},
      teams: {
        'Ops': ['mia', 'max'],
      },
      folders: {'prod': null},
    );
    await w.acl('prod', 'team:Ops', allow: ['view', 'connect']);
    await w.acl('prod', 'user:mia', allow: ['edit']);
    await w.keys('prod', 1, ['olivia', 'mia', 'max']);
  });
  tearDown(() => s.close());

  test('removeMember: seats, user ACL, keys, a pending rotation, then the membership', () async {
    await s.db.transaction(
      (tx) => removeMember(tx, w.orgId, w.id('mia'), 'member_removed'),
    );
    final mia = {'u': w.id('mia')};
    expect(await w.count('team_members', 'user_id = @u', mia), 0);
    expect(await w.count('acl_entries', 'principal_id = @u', mia), 0);
    expect(await w.count('folder_keys', 'user_id = @u', mia), 0);
    expect(await w.count('org_members', 'user_id = @u', mia), 0);
    final row = (await s.db.query(
      'SELECT reason, removed_user_ids FROM pending_rotations',
    )).single;
    expect(row['reason'], 'member_removed');
    expect(jsonDecode(row['removed_user_ids']! as String), [w.id('mia')]);
    expect(await w.count('folder_keys'), 2);
  });

  test('deleteTeam: team ACL, seats, team; rotation for whoever lost view or connect', () async {
    await s.db.transaction((tx) => deleteTeam(tx, w.orgId, w.teams['Ops']!));
    expect(
      (
        await w.count('teams'),
        await w.count('team_members'),
        await w.count('acl_entries', "principal_type = 'team'"),
      ),
      (0, 0, 0),
    );
    final row = (await s.db.query(
      'SELECT reason, removed_user_ids FROM pending_rotations',
    )).single;
    expect(row['reason'], 'team_deleted');
    expect(
      jsonDecode(row['removed_user_ids']! as String),
      [w.id('mia'), w.id('max')]..sort(),
      reason: 'mia keeps view through edit but loses connect',
    );
  });

  test(
    'deleteOrg: every org table emptied; users and the audit chain stay',
    () async {
      final host = await w.item(w['olivia'], folder: 'prod');
      expect((await w.put(w['olivia'], host, 0)).status, 200);
      final t = iso(s.clock.now());
      await s.db.execute(
        "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES (@i, 0, '{}', 2, @t)",
        {'i': host['id'], 't': t},
      );
      await s.db.execute(
        "INSERT INTO invites (id, token_hash, email, org_id, role, created_by, created_at, expires_at) "
        "VALUES (@id, 'h', 'x@y.z', @o, 'member', @u, @t, @t)",
        {'id': newId(), 'o': w.orgId, 'u': w.id('olivia'), 't': t},
      );
      await s.db.transaction((tx) => deleteOrg(tx, w.orgId));
      for (final table in [
        'folder_keys',
        'folder_key_history',
        'pending_rotations',
        'acl_entries',
        'team_members',
        'teams',
        'invites',
        'item_revisions',
        'items',
        'org_members',
        'orgs',
      ]) {
        expect(await w.count(table), 0, reason: table);
      }
      expect(await w.count('users'), 5);
    },
  );

  test('deleteUser: Instance Owner 403, last owner 409, else personal data and each membership', () async {
    await expectLater(
      s.db.transaction((tx) => deleteUser(tx, w.io.userId, actor: w.io.userId)),
      throwsApi(ApiErrorCode.forbidden),
    );
    await s.db.execute(
      "UPDATE org_members SET status = 'accepted' WHERE user_id = @u",
      {'u': w.id('oscar')},
    );
    await expectLater(
      s.db.transaction(
        (tx) => deleteUser(tx, w.id('olivia'), actor: w.io.userId),
      ),
      throwsApi(ApiErrorCode.conflict),
    );
    final mia = w['mia'];
    final mine = await testItem(mia);
    await s.put(
      '/api/v1/items/${mine['id']}',
      token: mia.accessToken,
      body: mine,
      headers: {'if-match': '0'},
    );
    final t = iso(s.clock.now());
    for (final key in [
      'acct:mia@example.org',
      'acct:mia@example.org|ip:1.2.3.4',
      'events:${mia.userId}',
      'invite-create:${mia.userId}',
      'mail:${mia.userId}',
      'ip:1.2.3.4',
      'acct:mia_x@example.org',
    ]) {
      await s.db.execute(
        'INSERT INTO login_attempts (key, count, window_start) VALUES (@k, 1, @t)',
        {'k': key, 't': t},
      );
    }
    await s.db.transaction(
      (tx) => deleteUser(tx, mia.userId, actor: w.io.userId),
    );
    final p = {'u': mia.userId};
    expect(await w.count('users', 'id = @u', p), 0);
    expect(await w.count('devices', 'user_id = @u', p), 0);
    expect(
      await w.count('refresh_tokens'),
      4,
      reason: 'one per remaining device',
    );
    expect(await w.count('items', 'id = @i', {'i': mine['id']}), 0);
    expect(await w.count('org_members', 'user_id = @u', p), 0);
    expect(
      await w.count('audit_ips', 'scope = @s', {'s': 'user:${mia.userId}'}),
      0,
    );
    expect(
      (await s.db.query(
        "SELECT key FROM login_attempts WHERE key <> 'ip:203.0.113.7' ORDER BY key",
      )).map((r) => r['key']),
      ['acct:mia_x@example.org', 'ip:1.2.3.4'],
    );
    expect(await w.count('pending_rotations'), 1);
  });
}
