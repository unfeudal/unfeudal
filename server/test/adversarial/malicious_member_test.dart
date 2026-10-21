// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  // The malicious member: view and connect on prod, manage on lab.
  late TestSession eve;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {
        'eve': 'member',
        'adam': 'admin',
        'vic': 'member',
        'ana': 'member',
      },
      accepted: {'ana'},
      teams: {
        'Ops': ['vic'],
      },
      folders: {'prod': null, 'lab': null, 'secret': null},
    );
    eve = w['eve'];
    await w.acl('prod', 'user:eve', allow: ['connect']);
    await w.acl('lab', 'user:eve', allow: ['manage']);
    await w.keys('prod', 1, ['olivia', 'eve']);
    await w.keys('secret', 1, ['olivia']);
  });
  tearDown(() => s.close());

  test(
    'writes: no edit, no root folder, no foreign org, no stale key version',
    () async {
      expect(
        (await w.put(eve, await w.item(eve, folder: 'prod'), 0)).status,
        403,
      );
      expect(
        (await w.put(eve, await w.item(eve, type: 'folder'), 0)).status,
        403,
      );
      final foreign = {...await w.item(eve, folder: 'prod'), 'orgId': newId()};
      expect((await w.put(eve, foreign, 0)).status, 404);
      final host = await w.item(w['olivia'], folder: 'prod');
      await w.put(w['olivia'], host, 0);
      expect(
        (await w.put(eve, {...host, 'deleted': true}, 1)).status,
        403,
        reason: 'delete needs edit',
      );
    },
  );

  test('rights: no escalation, not even to self through a team, no role or member admin', () async {
    Map<String, Object?> e(String type, String id, List<String> allow) => {
      'principalType': type,
      'principalId': id,
      'allow': allow,
      'deny': <String>[],
    };
    final self = await s.put(
      '/api/v1/folders/${w.folder('lab')}/acl',
      token: eve.accessToken,
      body: {
        'entries': [
          e('user', eve.userId, ['manage', 'edit']),
        ],
      },
    );
    expect(self.status, 403);
    final viaTeam = await s.put(
      '/api/v1/folders/${w.folder('lab')}/acl',
      token: eve.accessToken,
      body: {
        'entries': [
          e('user', eve.userId, ['manage']),
          e('team', w.teams['Ops']!, ['reveal']),
        ],
      },
    );
    expect(viaTeam.status, 403);
    expect(
      (await s.put(
        '/api/v1/folders/${w.folder('prod')}/acl',
        token: eve.accessToken,
        body: {'entries': <Object?>[]},
      )).status,
      403,
    );
    expect(
      (await s.put(
        '/api/v1/orgs/${w.orgId}/members/${eve.userId}',
        token: eve.accessToken,
        body: {'role': 'admin'},
      )).status,
      403,
    );
    expect(
      (await s.post(
        '/api/v1/orgs/${w.orgId}/members/${w.id('ana')}/confirm',
        token: eve.accessToken,
      )).status,
      403,
    );
    expect(
      (await s.delete(
        '/api/v1/orgs/${w.orgId}/members/${w.id('vic')}',
        token: eve.accessToken,
      )).status,
      403,
    );
    expect(
      (await s.post(
        '/api/v1/orgs/${w.orgId}/invites',
        token: eve.accessToken,
        body: {'email': 'x@y.z'},
      )).status,
      403,
    );
    expect(
      (await s.post(
        '/api/v1/orgs/${w.orgId}/teams',
        token: eve.accessToken,
        body: {'name': 'Mine'},
      )).status,
      403,
    );
  });

  test('keys: no upload for a folder she did not create, no secret for view-only, no rotation', () async {
    Future<int> keys(
      String folder,
      int version,
      List<Map<String, Object?>> wraps, [
      Map<String, Object?>? history,
    ]) async => (await s.put(
      '/api/v1/folders/${w.folder(folder)}/keys',
      token: eve.accessToken,
      body: {'version': version, 'wrapped': wraps, 'history': history},
    )).status;
    expect(await keys('secret', 1, [w.wrap('eve', 'secret', 1)]), 403);
    expect(
      await keys('prod', 2, [w.wrap('eve', 'prod', 2)], w.history('prod', 2)),
      403,
    );
    expect(await keys('lab', 1, [w.wrap('eve', 'lab', 1)]), 403);
    expect(
      (await s.post(
        '/api/v1/folders/${w.folder('prod')}/rotation/done',
        token: eve.accessToken,
      )).status,
      403,
    );
  });

  test(
    'reads: nothing outside her folders, no other wraps, no admin rows',
    () async {
      final page = await w.sync(eve);
      final folders = page.items
          .where((i) => i.type == 'folder')
          .map((i) => i.id)
          .toSet();
      expect(folders, {w.folder('prod'), w.folder('lab')});
      final b = page.org!;
      expect(b.wrappedKeys.map((k) => k.folderId), [w.folder('prod')]);
      expect(b.keyRequests, isEmpty);
      expect(b.pendingRotations, isEmpty);
      expect(b.teams, isEmpty);
      expect(
        b.members.every((m) => m.publicKey == null && m.status == null),
        isTrue,
      );
    },
  );

  test('removed member: no item, key or block row; old invites and stale tokens do not bring her back', () async {
    final invite = await s.post(
      '/api/v1/orgs/${w.orgId}/invites',
      token: w['adam'].accessToken,
      body: {'email': 'eve@example.org'},
    );
    final token = Enrollment.parseLink(
      (invite.body['invite']! as Map)['link']! as String,
    ).token;
    expect(
      (await s.delete(
        '/api/v1/invites/${(invite.body['invite']! as Map)['id']}',
        token: w['adam'].accessToken,
      )).status,
      204,
    );
    expect(
      (await s.delete(
        '/api/v1/orgs/${w.orgId}/members/${eve.userId}',
        token: w['adam'].accessToken,
      )).status,
      204,
    );
    final page = await w.sync(eve);
    expect(page.items, isEmpty);
    expect(page.org!.orgs, isEmpty);
    expect(page.org!.wrappedKeys, isEmpty);
    expect(
      (await s.post(
        '/api/v1/invites/join',
        token: eve.accessToken,
        body: {'token': token},
      )).status,
      404,
    );
    expect(
      (await w.put(eve, await w.item(eve, folder: 'prod'), 0)).status,
      404,
    );
  });

  test('an accepted member cannot use the org before confirmation', () async {
    final ana = w['ana'];
    expect(
      (await w.put(ana, await w.item(ana, folder: 'prod'), 0)).status,
      404,
    );
    expect(
      (await s.put(
        '/api/v1/folders/${w.folder('lab')}/acl',
        token: ana.accessToken,
        body: {'entries': <Object?>[]},
      )).status,
      404,
    );
    expect(
      (await s.post(
        '/api/v1/orgs/${w.orgId}/members/${ana.userId}/confirm',
        token: ana.accessToken,
      )).status,
      404,
    );
  });
}
