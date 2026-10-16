// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/errors.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fake_clock.dart';
import '../support/test_db.dart';

const u = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const d = '8c7b6a59-4e3d-4c2b-a190-8f7e6d5c4b3a';

void main() {
  late Db db;
  late FakeClock clock;
  late RefreshTokens refresh;
  final secret = List.filled(32, 9);

  setUp(() async {
    db = await openTestDb();
    await migrate(db);
    clock = FakeClock(DateTime.utc(2026, 10, 13, 12));
    refresh = RefreshTokens(db, clock, const Duration(days: 30), secret);
    final t = iso(clock.now());
    await db.execute(
      "INSERT INTO users (id, email, bundle, auth_hash, created_at) VALUES (@u, 'a@b.c', '{}', 'h', @t)",
      {'u': u, 't': t},
    );
    await db.execute(
      "INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) VALUES (@d, @u, 'n', 'linux', @t, @t)",
      {'d': d, 'u': u, 't': t},
    );
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> device() async => (await db.query(
    'SELECT revoked_at, last_seen_at FROM devices WHERE id = @d',
    {'d': d},
  )).single;
  Matcher unauthorized(UnauthorizedReason r) => throwsA(
    isA<ApiError>().having((e) => (e.code, e.extra['reason']), 'reason', (
      ApiErrorCode.unauthorized,
      r.wire,
    )),
  );

  test('rotate returns the successor of crypto.md, stores only hashes, touches last_seen_at', () async {
    final t = await db.transaction((tx) => refresh.create(tx, d));
    expect(t, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    clock.advance(const Duration(minutes: 6));
    final r = await refresh.rotate(t);
    expect(
      (r.userId, r.deviceId, r.refreshToken),
      (u, d, refreshSuccessor(secret, t)),
    );
    final rows = await db.query(
      'SELECT token_hash, expires_at, used_at FROM refresh_tokens ORDER BY expires_at',
    );
    expect(rows.map((x) => x['token_hash']), [
      hashToken(t),
      hashToken(r.refreshToken),
    ]);
    expect(
      rows.last['expires_at'],
      iso(clock.now().add(const Duration(days: 30))),
      reason: 'a successor gets a fresh expiry',
    );
    expect((await device())['last_seen_at'], iso(clock.now()));
    clock.advance(const Duration(minutes: 1));
    await refresh.rotate(r.refreshToken);
    expect(
      (await device())['last_seen_at'],
      isNot(iso(clock.now())),
      reason: 'at most every 5 min',
    );
  });

  test('a lost response within 30 s gets the same successor', () async {
    final t = await db.transaction((tx) => refresh.create(tx, d));
    final first = await refresh.rotate(t);
    clock.advance(const Duration(seconds: 30));
    expect((await refresh.rotate(t)).refreshToken, first.refreshToken);
  });

  test(
    'a replay after the grace revokes the device and its successor',
    () async {
      final t = await db.transaction((tx) => refresh.create(tx, d));
      final next = await refresh.rotate(t);
      clock.advance(const Duration(seconds: 31));
      await expectLater(
        refresh.rotate(t),
        unauthorized(UnauthorizedReason.deviceRevoked),
      );
      expect(
        (await device())['revoked_at'],
        iso(clock.now()),
        reason: 'committed before the 401',
      );
      await expectLater(
        refresh.rotate(next.refreshToken),
        unauthorized(UnauthorizedReason.deviceRevoked),
      );
    },
  );

  test(
    'a replay once the successor was used revokes even within 30 s',
    () async {
      final t = await db.transaction((tx) => refresh.create(tx, d));
      final next = await refresh.rotate(t);
      await refresh.rotate(next.refreshToken);
      await expectLater(
        refresh.rotate(t),
        unauthorized(UnauthorizedReason.deviceRevoked),
      );
    },
  );

  test('unknown, expired, revoked and disabled', () async {
    await expectLater(
      refresh.rotate('nope'),
      unauthorized(UnauthorizedReason.invalidToken),
    );
    final t = await db.transaction((tx) => refresh.create(tx, d));
    clock.advance(const Duration(days: 30));
    await expectLater(
      refresh.rotate(t),
      unauthorized(UnauthorizedReason.sessionExpired),
    );
    expect(
      (await device())['revoked_at'],
      isNull,
      reason: 'expiry keeps the device',
    );
    final t2 = await db.transaction((tx) => refresh.create(tx, d));
    await db.execute('UPDATE users SET disabled = 1');
    await expectLater(
      refresh.rotate(t2),
      unauthorized(UnauthorizedReason.deviceRevoked),
    );
  });

  test(
    'concurrent rotations of one token all get the same successor',
    () async {
      final t = await db.transaction((tx) => refresh.create(tx, d));
      final got = await Future.wait([
        for (var i = 0; i < 5; i++) refresh.rotate(t),
      ]);
      expect(got.map((r) => r.refreshToken).toSet(), {
        refreshSuccessor(secret, t),
      });
      expect((await device())['revoked_at'], isNull);
    },
  );

  test('revokeDevice sets revoked_at once and uses every token', () async {
    await db.transaction((tx) => refresh.create(tx, d));
    await db.transaction((tx) => revokeDevice(tx, d, clock.now()));
    clock.advance(const Duration(minutes: 1));
    await db.transaction((tx) => revokeDevice(tx, d, clock.now()));
    expect(
      (await device())['revoked_at'],
      iso(clock.now().subtract(const Duration(minutes: 1))),
    );
    expect(
      await db.query(
        'SELECT token_hash FROM refresh_tokens WHERE used_at IS NULL',
      ),
      isEmpty,
    );
  });
}
