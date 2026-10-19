// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'adam': 'admin', 'mia': 'member', 'max': 'member'},
      folders: {'prod': null, 'db': 'prod', 'web': null},
    );
  });
  tearDown(() => s.close());

  Future<TestResponse> audit(TestSession who, String query) =>
      s.get('/api/v1/audit?$query', token: who.accessToken);

  /// Pages a whole view, following next.
  Future<List<AuditEvent>> all(
    TestSession who,
    String scope, {
    int limit = 2,
  }) async {
    final out = <AuditEvent>[];
    String? after;
    do {
      final r = await audit(
        who,
        'scope=$scope&limit=$limit${after == null ? '' : '&after=$after'}',
      );
      expect(r.status, 200, reason: '${r.json}');
      out.addAll([
        for (final e in r.body['events']! as List) AuditEvent.fromJson(e),
      ]);
      after = r.body['next'] as String?;
    } while (after != null);
    return out;
  }

  test('malformed scope, id, limit or cursor → 400; feature off → 404 feature_disabled', () async {
    for (final q in [
      'scope=nope',
      'scope=org:XYZ',
      'scope=folder:1',
      'limit=0',
      'limit=501',
      'limit=x',
      'after=!!',
    ]) {
      expect((await audit(w['mia'], q)).status, 400, reason: q);
    }
    final off = await TestServer.start(
      env: {'UNFEUDAL_FEATURE_AUDIT': 'false'},
    );
    final o = await off.setupOwner();
    expect(
      (await off.get('/api/v1/audit', token: o.accessToken)).error,
      'feature_disabled',
    );
    await off.close();
  });

  test(
    'user: the caller\'s whole chain in seq order, paged; it verifies',
    () async {
      for (var i = 0; i < 4; i++) {
        await s.login('mia@example.org', testPassword);
      }
      final chain = await all(w['mia'], 'user');
      expect(chain.map((e) => e.seq), [1, 2, 3, 4, 5]);
      expect(
        chain.every(
          (e) => e.scope == 'user:${w.id('mia')}' && e.ipAddress == null,
        ),
        isTrue,
      );
      expect(verifyChain(chain), isNull);
    },
  );

  test(
    'a row deleted on the server breaks verification of the served chain',
    () async {
      for (var i = 0; i < 3; i++) {
        await s.login('mia@example.org', testPassword);
      }
      await s.db.execute(
        'DELETE FROM audit_events WHERE scope = @s AND seq = 2',
        {'s': 'user:${w.id('mia')}'},
      );
      expect(verifyChain(await all(w['mia'], 'user')), 3);
    },
  );

  test(
    'instance: Instance Owner only; only the Instance Owner gets raw IPs',
    () async {
      expect((await audit(w['olivia'], 'scope=instance')).status, 403);
      final chain = await all(w.io, 'instance');
      expect(
        [chain.first.action, chain.first.ipAddress],
        ['setup.completed', '203.0.113.7'],
      );
    },
  );

  test('org: admins read it, members 403, strangers 404, the Instance Owner 404 while it lives', () async {
    final scope = 'org:${w.orgId}';
    final zed = await s.createUser('zed@example.org');
    expect(
      [
        (await audit(w['mia'], 'scope=$scope')).status,
        (await audit(zed, 'scope=$scope')).status,
        (await audit(w.io, 'scope=$scope')).status,
      ],
      [403, 404, 404],
    );
    final chain = await all(w['adam'], scope);
    expect(chain.map((e) => e.action), [
      'item.created',
      'item.created',
      'item.created',
    ]);
    expect(chain.every((e) => e.ipAddress == null), isTrue);
    expect(verifyChain(chain), isNull);
    expect(
      (await s.delete(
        '/api/v1/orgs/${w.orgId}',
        token: w['olivia'].accessToken,
      )).status,
      204,
    );
    expect((await audit(w['adam'], 'scope=$scope')).status, 404);
    final kept = await all(w.io, scope);
    expect([kept.length, kept.first.ipAddress], [3, '203.0.113.7']);
  });

  test('me shows the caller\'s own actions only, across scopes, by (ts, scope, seq)', () async {
    final adam = w['adam'];
    s.clock.advance(const Duration(minutes: 1));
    await s.put(
      '/api/v1/orgs/${w.orgId}',
      token: adam.accessToken,
      body: {'name': 'Acme 2'},
    );
    s.clock.advance(const Duration(minutes: 1));
    await s.login('adam@example.org', testPassword);
    final mine = await all(adam, 'me', limit: 1);
    expect(mine.map((e) => [e.scope, e.action]), [
      ['user:${adam.userId}', 'device.added'],
      ['org:${w.orgId}', 'org.updated'],
      ['user:${adam.userId}', 'device.added'],
    ]);
    expect(mine.every((e) => e.actorUser == adam.userId), isTrue);
  });

  test('folder: manage holders and admins see events whose targets are in the subtree; others 403 or 404', () async {
    await w.acl('prod', 'user:mia', allow: ['manage']);
    final inDb = await w.item(w['olivia'], folder: 'db');
    final inWeb = await w.item(w['olivia'], folder: 'web');
    await w.put(w['olivia'], inDb, 0);
    await w.put(w['olivia'], inWeb, 0);
    final (prod, db) = (w.folder('prod'), w.folder('db'));
    final view = await all(w['mia'], 'folder:$prod', limit: 1);
    expect(view.map((e) => [e.action, ...e.targetIds]), [
      ['item.created', prod],
      ['item.created', db, prod],
      ['item.created', inDb['id'], db],
    ]);
    expect(await all(w['adam'], 'folder:$prod'), hasLength(3));
    final zed = await s.createUser('zed@example.org');
    expect(
      [
        (await audit(w['max'], 'scope=folder:$prod')).status,
        (await audit(w['mia'], 'scope=folder:${w.folder('web')}')).status,
        (await audit(zed, 'scope=folder:$prod')).status,
        (await audit(w['mia'], 'scope=folder:${newId()}')).status,
      ],
      [403, 403, 404, 404],
    );
  });
}
