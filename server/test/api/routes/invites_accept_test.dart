// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  Future<void> start([Map<String, String> env = const {}]) async {
    s = await TestServer.start(env: env);
    w = await OrgWorld.build(s, roles: {'mia': 'member'});
  }

  tearDown(() => s.close());

  Future<String> orgInvite(
    String email, {
    String by = 'olivia',
    String role = 'member',
  }) async {
    final r = await s.post(
      '/api/v1/orgs/${w.orgId}/invites',
      token: w[by].accessToken,
      body: {'email': email, 'role': role},
    );
    return Enrollment.parseLink((r.body['invite']! as Map)['link']! as String)
        .token;
  }

  /// Direct invite row valid one day: an org invite when [orgId] is set (by olivia unless [by]), else an
  /// instance invite (pass the Instance Owner as [by]).
  Future<String> rawInvite(String email, {String? orgId, String? by}) async {
    final token = b64(List.generate(32, (_) => Random.secure().nextInt(256)));
    await s.db.execute(
      'INSERT INTO invites (id, token_hash, email, org_id, role, created_by, created_at, expires_at) '
      'VALUES (@id, @h, @e, @o, @r, @u, @t, @x)',
      {
        'id': newId(),
        'h': hashToken(token),
        'e': email,
        'o': orgId,
        'r': orgId == null ? null : 'member',
        'u': by ?? w.id('olivia'),
        't': iso(s.clock.now()),
        'x': iso(s.clock.now().add(const Duration(days: 1))),
      },
    );
    return token;
  }

  Future<TestResponse> accept(
    String token,
    String email, {
    Map<String, Object?> over = const {},
    String ip = '198.51.100.9',
  }) async {
    final acc = await testCrypto.create(testPassword);
    return s.post(
      '/api/v1/invites/accept',
      ip: ip,
      body: {
        'token': token,
        'email': email,
        'bundle': acc.bundle.toJson(),
        'authKey': b64(acc.authKey),
        'recoveryAuthKey': b64(acc.recoveryAuthKey),
        'device': testDevice(),
        'locale': 'fr',
        ...over,
      },
    );
  }

  test('accept an org invite: new account, accepted member, session, org_seq + 1, invite-ip refunded', () async {
    await start();
    final token = await orgInvite('new@example.org', role: 'admin');
    final seq = await w.orgSeq();
    final r = await accept(token, 'new@example.org');
    expect(r.status, 201);
    final session = Session.fromJson(r.json);
    expect((session.isInstanceOwner, session.bundleVersion), (false, 0));
    final m = (await s.db.query(
      'SELECT role, status FROM org_members WHERE user_id = @u',
      {'u': session.userId},
    )).single;
    expect((m['role'], m['status']), ('admin', 'accepted'));
    expect(
      (await s.db.query('SELECT locale FROM users WHERE id = @u', {
        'u': session.userId,
      })).single['locale'],
      'fr',
    );
    expect(await w.count('invites', 'accepted_at IS NOT NULL'), 1);
    expect(await w.orgSeq(), seq + 1);
    expect(
      await w.count(
        'login_attempts',
        "key = 'invite-ip:198.51.100.9' AND count > 0",
      ),
      0,
    );
  });

  test('accept an instance invite: account only, org_seq unchanged', () async {
    await start();
    final token = await rawInvite('solo@example.org', by: w.io.userId);
    final seq = await w.orgSeq();
    final r = await accept(token, 'solo@example.org');
    expect(r.status, 201);
    expect(
      await w.count('org_members', 'user_id = @u', {
        'u': Session.fromJson(r.json).userId,
      }),
      0,
    );
    expect(await w.orgSeq(), seq);
  });

  test(
    'two simultaneous accepts of one invite: one account, the other is 404',
    () async {
      await start();
      final token = await orgInvite('new@example.org');
      final rs = await Future.wait([
        accept(token, 'new@example.org'),
        accept(token, 'new@example.org'),
      ]);
      expect(rs.map((r) => r.status).toList()..sort(), [201, 404]);
      expect(await w.count('users', "email = 'new@example.org'"), 1);
    },
  );

  test(
    'a used, revoked, expired or other-email token is 404 with one message',
    () async {
      await start();
      final used = await orgInvite('used@example.org');
      await accept(used, 'used@example.org');
      final revoked = await orgInvite('rev@example.org');
      await s.db.execute(
        "UPDATE invites SET revoked_at = expires_at WHERE email = 'rev@example.org'",
      );
      final other = await orgInvite('right@example.org');
      final expired = await orgInvite('old@example.org');
      s.clock.advance(const Duration(days: 7, seconds: 1));
      final results = [
        await accept(b64(List.filled(32, 7)), 'x@example.org'),
        await accept(used, 'used@example.org'),
        await accept(revoked, 'rev@example.org'),
        await accept(other, 'wrong@example.org'),
        await accept(expired, 'old@example.org'),
      ];
      expect(results.map((r) => (r.status, r.body['message'])).toSet(), {
        (404, 'This invitation is not valid.'),
      });
    },
  );

  test('existing account is 409 account_exists; bad bundle, device or keys are 400', () async {
    await start();
    final token = await orgInvite('mia@example.org');
    final r = await accept(token, 'mia@example.org');
    expect((r.status, r.body['reason']), (409, 'account_exists'));
    final fresh = await orgInvite('fresh@example.org');
    for (final over in <Map<String, Object?>>[
      {'bundle': {}},
      {
        'device': {'name': '', 'platform': 'linux'},
      },
      {'authKey': 'short'},
    ]) {
      expect(
        (await accept(fresh, 'fresh@example.org', over: over)).status,
        400,
        reason: '$over',
      );
    }
    expect((await accept('x' * 201, 'fresh@example.org')).status, 400);
  });

  test(
    'orgs off: org invites are feature_disabled, instance invites still work',
    () async {
      await start({'UNFEUDAL_FEATURE_ORGS': 'false'});
      final orgToken = await rawInvite('o@example.org', orgId: w.orgId);
      final r = await accept(orgToken, 'o@example.org');
      expect((r.status, r.error), (404, 'feature_disabled'));
      expect(
        (await accept(
          await rawInvite('i@example.org', by: w.io.userId),
          'i@example.org',
        )).status,
        201,
      );
    },
  );

  test('invites_from_orgs off: only Instance Owner invites work, with the same 404', () async {
    await start({'UNFEUDAL_FEATURE_INVITES_FROM_ORGS': 'false'});
    final byOwner = await orgInvite('a@example.org');
    expect(
      (await accept(byOwner, 'a@example.org')).body['message'],
      'This invitation is not valid.',
    );
    await s.db.execute(
      "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, 'owner', 'confirmed')",
      {'o': w.orgId, 'u': w.io.userId},
    );
    final r = await s.post(
      '/api/v1/orgs/${w.orgId}/invites',
      token: w.io.accessToken,
      body: {'email': 'b@example.org'},
    );
    final byIo = Enrollment.parseLink(
      (r.body['invite']! as Map)['link']! as String,
    ).token;
    expect((await accept(byIo, 'b@example.org')).status, 201);
  });

  test(
    'invite-ip is counted before the token is read and refunded on success',
    () async {
      await start();
      final good = await orgInvite('good@example.org');
      for (var i = 0; i < 10; i++) {
        await accept(b64(List.filled(32, i)), 'nobody@example.org');
      }
      final r = await accept(good, 'good@example.org');
      expect((r.status, r.error), (429, 'rate_limited'));
      expect(
        (await accept(good, 'good@example.org', ip: '198.51.100.10')).status,
        201,
      );
    },
  );

  test(
    'join: an existing account accepts an org invite for its own email',
    () async {
      await start();
      final bob = await s.createUser('bob@example.org');
      final token = await orgInvite('bob@example.org');
      final seq = await w.orgSeq();
      final r = await s.post(
        '/api/v1/invites/join',
        token: bob.accessToken,
        body: {'token': token},
      );
      expect(r.status, 200);
      expect(r.body, {'orgId': w.orgId});
      expect(
        (await s.db.query('SELECT status FROM org_members WHERE user_id = @u', {
          'u': bob.userId,
        })).single['status'],
        'accepted',
      );
      expect(await w.orgSeq(), seq + 1);
      final again = await orgInvite('bob@example.org');
      expect(
        (await s.post(
          '/api/v1/invites/join',
          token: bob.accessToken,
          body: {'token': again},
        )).status,
        200,
      );
      expect(
        await w.count('org_members', 'user_id = @u', {'u': bob.userId}),
        1,
        reason: 'already a member: no second row',
      );
    },
  );

  test('join refusals: other email 404, instance invite 409 and left unused, cap 403, flags', () async {
    await start({'UNFEUDAL_MAX_ORGS_PER_USER': '1'});
    final bob = await s.createUser('bob@example.org');
    Future<TestResponse> join(String token, [TestSession? who]) => s.post(
      '/api/v1/invites/join',
      token: (who ?? bob).accessToken,
      body: {'token': token},
    );
    expect((await join(await orgInvite('carl@example.org'))).status, 404);
    final inst = await rawInvite('bob@example.org', by: w.io.userId);
    final r = await join(inst);
    expect((r.status, r.body['reason']), (409, 'account_exists'));
    expect(
      await w.count('invites', 'accepted_at IS NULL AND org_id IS NULL'),
      1,
    );
    expect((await join(await orgInvite('bob@example.org'))).status, 200);
    final beta = newId();
    await s.db.execute(
      "INSERT INTO orgs (id, name, created_at) VALUES (@o, 'Beta', @t)",
      {'o': beta, 't': iso(s.clock.now())},
    );
    expect(
      (await join(await rawInvite('bob@example.org', orgId: beta))).status,
      403,
      reason: 'bob already has one org',
    );
    expect((await join('')).status, 400);
  });
}
