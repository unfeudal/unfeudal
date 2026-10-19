// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/audit.dart';
import '../../support/items.dart';
import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  late Map<String, Object?> orgHost, orgJump, orgIdentity, mine, mineJump, hers;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'mia': 'member', 'max': 'member'},
      folders: {'prod': null},
    );
    await w.acl('prod', 'user:mia', allow: ['reveal']);
    await w.acl('prod', 'user:max', allow: ['view']);
    orgHost = await w.item(w['olivia'], folder: 'prod');
    orgJump = await w.item(w['olivia'], folder: 'prod');
    orgIdentity = await w.item(
      w['olivia'],
      type: 'identity',
      folder: 'prod',
      secret: true,
    );
    for (final i in [orgHost, orgJump, orgIdentity]) {
      await w.put(w['olivia'], i, 0);
    }
    mine = await testItem(w['mia']);
    mineJump = await testItem(w['mia']);
    hers = await testItem(w['olivia']);
    for (final (who, i) in [
      (w['mia'], mine),
      (w['mia'], mineJump),
      (w['olivia'], hers),
    ]) {
      await s.put(
        '/api/v1/items/${i['id']}',
        token: who.accessToken,
        body: i,
        headers: {'if-match': '0'},
      );
    }
  });
  tearDown(() => s.close());

  Future<TestResponse> ssh(TestSession who, Object body) =>
      s.post('/api/v1/events/ssh', token: who.accessToken, body: body);
  Future<TestResponse> reveal(TestSession who, Object? id) => s.post(
    '/api/v1/events/reveal',
    token: who.accessToken,
    body: {'itemId': id},
  );

  test('ssh events land in the host scope; jump hosts of another scope are left out', () async {
    final mia = w['mia'];
    expect(
      (await ssh(mia, {
        'event': 'open',
        'hostItemId': orgHost['id'],
        'jumpHostItemIds': [orgJump['id'], mineJump['id']],
      })).status,
      204,
    );
    expect(
      (await ssh(mia, {'event': 'close', 'hostItemId': orgHost['id']})).status,
      204,
    );
    expect(
      (await ssh(mia, {
        'event': 'forward_start',
        'hostItemId': mine['id'],
        'localPort': 5432,
      })).status,
      204,
    );
    expect(
      (await ssh(mia, {
        'event': 'forward_stop',
        'hostItemId': mine['id'],
        'localPort': 5432,
      })).status,
      204,
    );
    expect((await actions(s, 'org:${w.orgId}')).skip(4), [
      // folder + 3 items
      ['ssh.session_opened', orgHost['id'], orgJump['id']],
      ['ssh.session_closed', orgHost['id']],
    ]);
    expect((await actions(s, 'user:${mia.userId}')).skip(3), [
      // device.added + 2 items
      ['ssh.forward_started', mine['id'], 'forward:5432'],
      ['ssh.forward_stopped', mine['id'], 'forward:5432'],
    ]);
    expect(
      (await auditEvents(s, 'user:${mia.userId}')).last.actorDevice,
      mia.deviceId,
    );
  });

  test('reveal: item.revealed [itemId, folderId?] in the item scope', () async {
    expect((await reveal(w['mia'], orgIdentity['id'])).status, 204);
    expect((await reveal(w['mia'], mine['id'])).status, 204);
    expect((await actions(s, 'org:${w.orgId}')).last, [
      'item.revealed',
      orgIdentity['id'],
      w.folder('prod'),
    ]);
    expect((await actions(s, 'user:${w.id('mia')}')).last, [
      'item.revealed',
      mine['id'],
    ]);
  });

  test('refusals: no connect or reveal, another account, deleted, unknown → 404; malformed → 400', () async {
    final (mia, max) = (w['mia'], w['max']);
    await s.put(
      '/api/v1/items/${mine['id']}',
      token: mia.accessToken,
      body: {...mine, 'deleted': true},
      headers: {'if-match': '1'},
    );
    for (final (who, body) in [
      (max, {'event': 'open', 'hostItemId': orgHost['id']}),
      (mia, {'event': 'open', 'hostItemId': hers['id']}),
      (mia, {'event': 'open', 'hostItemId': mine['id']}),
      (mia, {'event': 'open', 'hostItemId': newId()}),
      (
        mia,
        {
          'event': 'open',
          'hostItemId': orgHost['id'],
          'jumpHostItemIds': [hers['id']],
        },
      ),
    ]) {
      expect((await ssh(who, body)).status, 404, reason: '$body');
    }
    expect(
      [
        (await reveal(max, orgIdentity['id'])).status,
        (await reveal(mia, hers['id'])).status,
      ],
      [404, 404],
    );
    for (final body in [
      {'event': 'open'},
      {'event': 'start', 'hostItemId': orgHost['id']},
      {'event': 'open', 'hostItemId': 'x'},
      {
        'event': 'open',
        'hostItemId': orgHost['id'],
        'jumpHostItemIds': [for (var i = 0; i < 9; i++) orgJump['id']],
      },
      {'event': 'forward_start', 'hostItemId': orgHost['id']},
      {'event': 'forward_start', 'hostItemId': orgHost['id'], 'localPort': 0},
      {
        'event': 'forward_stop',
        'hostItemId': orgHost['id'],
        'localPort': 65536,
      },
    ]) {
      expect((await ssh(mia, body)).status, 400, reason: '$body');
    }
    expect((await reveal(mia, 'x')).status, 400);
  });

  test(
    'the 121st event in a minute is 429, counted before the body is read',
    () async {
      final mia = w['mia'];
      for (var i = 0; i < 120; i++) {
        expect((await ssh(mia, 'not json')).status, 400);
      }
      final r = await reveal(mia, orgIdentity['id']);
      expect((r.status, r.error), (429, 'rate_limited'));
      s.clock.advance(const Duration(minutes: 1));
      expect((await reveal(mia, orgIdentity['id'])).status, 204);
    },
  );

  test('client_events off → 404 feature_disabled on both routes', () async {
    final off = await TestServer.start(
      env: {'UNFEUDAL_FEATURE_CLIENT_EVENTS': 'false'},
    );
    final o = await off.setupOwner();
    for (final p in ['/api/v1/events/ssh', '/api/v1/events/reveal']) {
      expect(
        (await off.post(p, token: o.accessToken, body: const {})).error,
        'feature_disabled',
      );
    }
    await off.close();
  });
}
