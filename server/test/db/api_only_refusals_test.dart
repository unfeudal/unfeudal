// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/items.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'mia': 'member'},
      teams: {
        'Ops': ['mia'],
      },
      folders: {'prod': null},
    );
  });
  tearDown(() => s.close());

  const t = '2026-10-13T12:00:00.000Z';
  // Throws if the schema refuses the row.
  Future<void> stored(String sql, [Map<String, Object?> p = const {}]) =>
      s.db.execute(sql, p);
  Map<String, Object?> entry(
    String type,
    String id, {
    List<String> allow = const ['view'],
    List<String> deny = const [],
  }) => {
    'principalType': type,
    'principalId': id,
    'allow': allow,
    'deny': deny,
  };
  Future<int> acl(List<Map<String, Object?>> entries) async => (await s.put(
    '/api/v1/folders/${w.folder('prod')}/acl',
    token: w['olivia'].accessToken,
    body: {'entries': entries},
  )).status;

  test(
    'roles: any text is stored, the API takes owner, admin or member',
    () async {
      final x = await s.createUser('x@example.org');
      await stored(
        "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, 'superuser', 'confirmed')",
        {'o': w.orgId, 'u': x.userId},
      );
      expect(
        (await s.put(
          '/api/v1/orgs/${w.orgId}/members/${w.id('mia')}',
          token: w['olivia'].accessToken,
          body: {'role': 'superuser'},
        )).status,
        400,
      );
    },
  );

  test('ACL: unknown permission, a principal outside the org and a team deny are stored, never accepted', () async {
    await stored(
      "INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) VALUES (@o, @f, 'user', 'nobody', '[\"root\"]', '[]')",
      {'o': w.orgId, 'f': w.folder('prod')},
    );
    await stored(
      "INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) VALUES (@o, @f, 'team', @t, '[]', '[\"view\"]')",
      {'o': w.orgId, 'f': w.folder('prod'), 't': w.teams['Ops']},
    );
    expect(
      await acl([
        entry('user', w.id('mia'), allow: ['root']),
      ]),
      400,
    );
    expect(await acl([entry('user', newId())]), 400);
    expect(
      await acl([
        entry('team', w.teams['Ops']!, deny: ['view']),
      ]),
      400,
    );
  });

  test('locale, device platform and org name length are API rules', () async {
    final mia = w['mia'];
    await stored("UPDATE users SET locale = 'de' WHERE id = @u", {
      'u': mia.userId,
    });
    expect(
      (await s.put(
        '/api/v1/account/locale',
        token: mia.accessToken,
        body: {'locale': 'de'},
      )).status,
      400,
    );
    await stored(
      "INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) VALUES ('d-beos', @u, 'n', 'beos', '$t', '$t')",
      {'u': mia.userId},
    );
    final login = await s.post(
      '/api/v1/login',
      body: {
        'email': mia.email,
        'authKey': b64(List.filled(32, 1)),
        'device': {'name': 'n', 'platform': 'beos'},
      },
    );
    expect(login.status, 400);
    await stored("UPDATE orgs SET name = @n WHERE id = @o", {
      'n': 'x' * 101,
      'o': w.orgId,
    });
    expect(
      (await s.post(
        '/api/v1/orgs',
        token: mia.accessToken,
        body: {'name': 'x' * 101},
      )).status,
      400,
    );
  });

  test('personal items: unknown folder, cycle, long type and type change are API rules', () async {
    final mia = w['mia'];
    await stored(
      "INSERT INTO items (id, owner_user_id, type, folder_id, revision, body, size, created_at, updated_at, seq) VALUES ('r1', @u, @ty, 'nowhere', 1, '{}', 2, '$t', '$t', 900)",
      {'u': mia.userId, 'ty': 'x' * 65},
    );
    Future<int> put(Map<String, Object?> item, int rev) async => (await s.put(
      '/api/v1/items/${item['id']}',
      token: mia.accessToken,
      body: item,
      headers: {'if-match': '$rev'},
    )).status;
    expect(await put(await testItem(mia, folderId: newId()), 0), 400);
    expect(await put({...await testItem(mia), 'type': 'x' * 65}, 0), 400);
    final a = await testItem(mia, type: 'folder');
    expect(await put(a, 0), 200);
    final b = await testItem(mia, type: 'folder', folderId: a['id']! as String);
    expect(await put(b, 0), 200);
    expect(
      await put(
        await testItem(
          mia,
          id: a['id']! as String,
          type: 'folder',
          folderId: b['id']! as String,
        ),
        1,
      ),
      400,
    );
    final host = await testItem(mia);
    expect(await put(host, 0), 200);
    expect(
      await put(
        await testItem(mia, id: host['id']! as String, type: 'snippet'),
        1,
      ),
      400,
    );
  });

  test('emails: the schema is case-sensitive, the API normalises', () async {
    await stored(
      "INSERT INTO users (id, email, bundle, auth_hash, created_at) VALUES ('u-mixed', 'MIA@example.org', '{}', 'h', '$t')",
    );
    final again = await s.login('  MIA@Example.org ', testPassword);
    expect(again.userId, w.id('mia'));
  });
}
