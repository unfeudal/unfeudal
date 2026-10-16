// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/errors.dart';
import 'package:unfeudal_server/src/auth/rate_limit.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fake_clock.dart';
import '../support/matchers.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late FakeClock clock;
  late RateLimiter limiter;
  final config = Config.load({
    'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
    'UNFEUDAL_LOGIN_MAX_ATTEMPTS': '3',
  });
  final ip = ipKey('198.51.100.4'),
      acctIp = acctIpKey('a@b.c', '198.51.100.4'),
      acct = acctKey('a@b.c');

  setUp(() async {
    db = await openTestDb();
    await migrate(db);
    clock = FakeClock(DateTime.utc(2026, 10, 13, 12));
    limiter = RateLimiter(db, clock, config);
  });
  tearDown(() => db.close());

  Future<int?> count(String key) async =>
      (await db.query('SELECT count FROM login_attempts WHERE key = @k', {
            'k': key,
          })).firstOrNull?['count']
          as int?;

  test('key builders', () {
    expect(
      [
        ip,
        acctIp,
        acct,
        inviteIpKey('n'),
        eventsKey('u'),
        inviteCreateKey('u'),
        mailKey('u'),
      ],
      [
        'ip:198.51.100.4',
        'acct:a@b.c|ip:198.51.100.4',
        'acct:a@b.c',
        'invite-ip:n',
        'events:u',
        'invite-create:u',
        'mail:u',
      ],
    );
  });

  test('the attempt reaching max locks the key; the next is 429 with retry-after; nothing counted', () async {
    for (var i = 0; i < 3; i++) {
      await limiter.hit([ip, acctIp]);
    }
    clock.advance(const Duration(minutes: 5));
    try {
      await limiter.hit([ip, acctIp]);
      fail('not limited');
    } on ApiError catch (e) {
      expect((e.code, e.retryAfter), (ApiErrorCode.rateLimited, 600));
    }
    expect((await count(ip), await count(acctIp)), (3, 3));
    clock.advance(const Duration(minutes: 10));
    await limiter.hit([ip, acctIp]);
    expect(await count(ip), 1, reason: 'window ended: counting restarts');
  });

  test('a locked ip key is refused before any row is inserted', () async {
    for (var i = 0; i < 3; i++) {
      await limiter.hit([ip]);
    }
    await expectLater(
      limiter.hit([ip, acctKey('new@b.c')]),
      throwsApi(ApiErrorCode.rateLimited),
    );
    expect(await count(acctKey('new@b.c')), isNull);
  });

  test('acct: each attempt bars the next for 1 s, 2 s, 4 s… 30 s; a barred attempt is not counted; reset clears', () async {
    final waits = <int>[];
    for (var i = 0; i < 7; i++) {
      await limiter.hit([acct]);
      try {
        await limiter.hit([acct]);
        fail('not barred');
      } on ApiError catch (e) {
        waits.add(e.retryAfter!);
      }
      clock.advance(Duration(seconds: waits.last));
    }
    expect(waits, [1, 2, 4, 8, 16, 30, 30]);
    expect(await count(acct), 7);
    await limiter.reset([acct]);
    await limiter.hit([acct]);
  });

  test(
    'parallel attempts on one account: one passes, the others are barred',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          limiter.hit([acct]).then((_) => true, onError: (Object _) => false),
      ]);
      expect(results.where((ok) => ok), hasLength(1));
      expect(await count(acct), 1);
    },
  );

  test(
    'refund lowers a count once; quota keys use their fixed limits',
    () async {
      final invite = inviteIpKey('198.51.100.4');
      await limiter.hit([invite]);
      await limiter.refund(invite);
      await limiter.refund(invite);
      expect(await count(invite), 0);
      for (var i = 0; i < 120; i++) {
        await limiter.hit([eventsKey('u')]);
      }
      await expectLater(
        limiter.hit([eventsKey('u')]),
        throwsApi(ApiErrorCode.rateLimited),
      );
      clock.advance(const Duration(minutes: 1));
      await limiter.hit([eventsKey('u')]);
      await limiter.hit([mailKey('u')]);
      await expectLater(
        limiter.hit([mailKey('u')]),
        throwsApi(ApiErrorCode.rateLimited),
      );
      for (var i = 0; i < 50; i++) {
        await limiter.hit([inviteCreateKey('u')]);
      }
      await expectLater(
        limiter.hit([inviteCreateKey('u')]),
        throwsApi(ApiErrorCode.rateLimited),
      );
    },
  );

  test('concurrent hits never pass the max', () async {
    final results = await Future.wait([
      for (var i = 0; i < 12; i++)
        limiter
            .hit([ip, acctIp])
            .then((_) => true, onError: (Object _) => false),
    ]);
    expect(results.where((ok) => ok), hasLength(3));
    expect(await count(ip), 3);
  });
}
