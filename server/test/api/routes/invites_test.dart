// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/fake_mailer.dart';
import '../../support/org_world.dart';
import '../../support/test_server.dart';

const smtp = {
  'UNFEUDAL_SMTP_HOST': 'smtp.test',
  'UNFEUDAL_SMTP_FROM': 'vault@example.org',
  'UNFEUDAL_FEATURE_SECURITY_EMAILS': 'false', // invite mails only
};

void main() {
  late TestServer s;
  late OrgWorld w;
  late FakeMailer mail;
  Future<void> start([Map<String, String> env = const {}]) async {
    mail = FakeMailer();
    s = await TestServer.start(env: env, mailer: mail);
    w = await OrgWorld.build(s, roles: {'adam': 'admin', 'mia': 'member'});
  }

  tearDown(() => s.close());

  Future<TestResponse> invite(String who, Object? email, [String? role]) =>
      s.post(
        '/api/v1/orgs/${w.orgId}/invites',
        token: w[who].accessToken,
        body: {'email': email, 'role': ?role},
      );

  test('creates an invite: link and file, hashed token, expiry, no mail without SMTP', () async {
    await start();
    final seq = await w.orgSeq();
    final r = await invite('adam', ' New@Example.org ');
    expect(r.status, 201);
    final inv = r.body['invite']! as Map<String, Object?>;
    expect(
      (inv['email'], inv['role'], inv['expiresAt'], r.body['mailSent']),
      (
        'new@example.org',
        'member',
        iso(s.clock.now().add(const Duration(days: 7))),
        false,
      ),
    );
    final link = Enrollment.parseLink(inv['link']! as String);
    expect(
      (link.server, link.kind),
      (Uri.parse('https://vault.test'), EnrollKind.invite),
    );
    expect(
      (await Enrollment.parseFile(inv['file']! as String)).token,
      link.token,
    );
    final row = (await s.db.query(
      'SELECT token_hash, org_id, role, created_by FROM invites WHERE id = @i',
      {'i': inv['id']},
    )).single;
    expect(row, {
      'token_hash': hashToken(link.token),
      'org_id': w.orgId,
      'role': 'member',
      'created_by': w.id('adam'),
    });
    expect(mail.sent, isEmpty);
    expect(await w.orgSeq(), seq, reason: 'invites are not in the block');
    expect(s.logLines.join(), isNot(contains(link.token)));
  });

  test(
    'creating an invite answers the same for known and unknown emails',
    () async {
      await start();
      final known = await invite('adam', 'mia@example.org');
      final unknown = await invite('adam', 'nobody@example.org');
      expect((known.status, unknown.status), (201, 201));
      expect(
        (known.body['invite']! as Map).keys,
        (unknown.body['invite']! as Map).keys,
      );
    },
  );

  test('role rules: admin and owner invites need an owner; members and strangers cannot invite', () async {
    await start();
    expect((await invite('adam', 'a@b.c', 'admin')).status, 403);
    expect((await invite('olivia', 'a@b.c', 'owner')).status, 201);
    expect((await invite('mia', 'a@b.c')).status, 403);
    expect(
      (await s.post(
        '/api/v1/orgs/${w.orgId}/invites',
        token: w.io.accessToken,
        body: {'email': 'a@b.c'},
      )).status,
      404,
    );
    for (final (email, role) in [('not-an-email', null), ('a@b.c', 'boss')]) {
      expect((await invite('olivia', email, role)).status, 400);
    }
  });

  test('mail after commit: SMTP and smtp_invites on; a failure is mailSent false and keeps the invite', () async {
    await start(smtp);
    final r = await invite('adam', 'x@example.org');
    expect(r.body['mailSent'], isTrue);
    final m = mail.sent.single;
    expect(
      (m.kind.name, m.to, m.locale, m.vars['link']),
      ('invite', 'x@example.org', 'en', (r.body['invite']! as Map)['link']),
    );
    mail.fail = true;
    final failed = await invite('adam', 'y@example.org');
    expect((failed.status, failed.body['mailSent']), (201, false));
    expect(await w.count('invites', 'email = @e', {'e': 'y@example.org'}), 1);
    expect(
      s.logLines.where((l) => l.contains('invite mail failed')),
      hasLength(1),
    );
    expect(s.logLines.where((l) => l.contains('y@example.org')), isEmpty);
    await s.close();
    await start({...smtp, 'UNFEUDAL_FEATURE_SMTP_INVITES': 'false'});
    expect((await invite('adam', 'z@example.org')).body['mailSent'], isFalse);
    expect(mail.sent, isEmpty);
  });

  test('invite-create: 50 per caller per day', () async {
    await start();
    for (var i = 0; i < 50; i++) {
      expect((await invite('adam', 'u$i@example.org')).status, 201);
    }
    final r = await invite('adam', 'last@example.org');
    expect((r.status, r.error), (429, 'rate_limited'));
    expect((await invite('olivia', 'last@example.org')).status, 201);
  });

  test('list: pending only, by expiresAt', () async {
    await start();
    final a = (await invite('adam', 'a@example.org')).body['invite']! as Map;
    s.clock.advance(const Duration(minutes: 1)); // within the access token TTL
    final b = (await invite('adam', 'b@example.org')).body['invite']! as Map;
    final c = (await invite('adam', 'c@example.org')).body['invite']! as Map;
    await s.db.execute('UPDATE invites SET revoked_at = @t WHERE id = @i', {
      't': iso(s.clock.now()),
      'i': c['id'],
    });
    final r = await s.get(
      '/api/v1/orgs/${w.orgId}/invites',
      token: w['adam'].accessToken,
    );
    expect((r.body['invites']! as List).map((i) => (i as Map)['id']), [
      a['id'],
      b['id'],
    ]);
    expect(((r.body['invites']! as List).first as Map).keys, [
      'id',
      'email',
      'role',
      'createdBy',
      'createdAt',
      'expiresAt',
    ]);
    s.clock.advance(
      const Duration(days: 7) - const Duration(seconds: 1),
    ); // a expired, b not yet
    final adam = await s.login(w['adam'].email, w['adam'].password);
    final mia = await s.login(w['mia'].email, w['mia'].password);
    final later = await s.get(
      '/api/v1/orgs/${w.orgId}/invites',
      token: adam.accessToken,
    );
    expect((later.body['invites']! as List).map((i) => (i as Map)['id']), [
      b['id'],
    ]);
    expect(
      (await s.get(
        '/api/v1/orgs/${w.orgId}/invites',
        token: mia.accessToken,
      )).status,
      403,
    );
  });

  test('revoke: who may manage it, then owner rule, then accepted', () async {
    await start();
    final member =
        (await invite('adam', 'a@example.org')).body['invite']! as Map;
    final admin =
        (await invite('olivia', 'b@example.org', 'admin')).body['invite']!
            as Map;
    final instanceId = newId(); // instance invite row
    await s.db.execute(
      'INSERT INTO invites (id, token_hash, email, org_id, role, created_by, created_at, expires_at) '
      "VALUES (@id, 'h-instance', 'c@example.org', NULL, NULL, @u, @t, @x)",
      {
        'id': instanceId,
        'u': w.io.userId,
        't': iso(s.clock.now()),
        'x': iso(s.clock.now().add(const Duration(days: 1))),
      },
    );
    Future<int> revoke(String? who, Object? id, {String? token}) async =>
        (await s.delete(
          '/api/v1/invites/$id',
          token: token ?? w[who!].accessToken,
        )).status;
    expect(await revoke('mia', member['id']), 404);
    expect(await revoke('adam', admin['id']), 403);
    expect(await revoke('olivia', instanceId), 404);
    expect(await revoke('adam', newId()), 404);
    expect(await revoke('adam', member['id']), 204);
    final at = (await s.db.query(
      'SELECT revoked_at FROM invites WHERE id = @i',
      {'i': member['id']},
    )).single['revoked_at'];
    s.clock.advance(const Duration(minutes: 1));
    expect(await revoke('adam', member['id']), 204);
    expect(
      (await s.db.query('SELECT revoked_at FROM invites WHERE id = @i', {
        'i': member['id'],
      })).single['revoked_at'],
      at,
    );
    await s.db.execute('UPDATE invites SET accepted_at = @t WHERE id = @i', {
      't': iso(s.clock.now()),
      'i': admin['id'],
    });
    expect(await revoke('olivia', admin['id']), 409);
    expect(await revoke(null, instanceId, token: w.io.accessToken), 204);
  });
}
