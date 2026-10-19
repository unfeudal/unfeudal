// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../config/config.dart';
import '../db/db.dart';
import '../util/clock.dart';

String ipKey(String net) => 'ip:$net';
String acctIpKey(String email, String net) => 'acct:$email|ip:$net';
String acctKey(String email) => 'acct:$email';
String inviteIpKey(String net) => 'invite-ip:$net';
String eventsKey(String userId) => 'events:$userId';
String inviteCreateKey(String userId) => 'invite-create:$userId';
String mailKey(String userId) => 'mail:$userId';

class _Limit {
  const _Limit(this.max, this.window, this.lock);

  /// Null for `acct:`, barred after each attempt by its delay instead.
  final int? max;
  final Duration window;
  final Duration lock;
}

class RateLimiter {
  RateLimiter(this.db, this.clock, this.config);

  final Db db;
  final Clock clock;
  final Config config;

  /// Called after commit with the email of each `acct:<email>|ip:<net>` key the hit locked.
  void Function(String email)? onLockout;

  _Limit _limitOf(String key) {
    final login = _Limit(
      config.loginMaxAttempts,
      config.loginLockout,
      config.loginLockout,
    );
    if (key.startsWith('ip:') ||
        key.startsWith('invite-ip:') ||
        (key.startsWith('acct:') && key.contains('|ip:'))) {
      return login;
    }
    if (key.startsWith('acct:')) {
      return _Limit(null, config.loginLockout, Duration.zero);
    }
    if (key.startsWith('events:')) {
      return const _Limit(120, Duration(minutes: 1), Duration(minutes: 1));
    }
    if (key.startsWith('invite-create:')) {
      return const _Limit(50, Duration(hours: 24), Duration(hours: 24));
    }
    if (key.startsWith('mail:')) {
      return const _Limit(1, Duration(hours: 1), Duration(hours: 1));
    }
    throw ArgumentError.value(key, 'key');
  }

  static DateTime? _lockedUntil(Map<String, Object?>? row, DateTime now) {
    final until = row?['locked_until'] as String?;
    return until != null && parseIso(until).isAfter(now)
        ? parseIso(until)
        : null;
  }

  static Never _limited(DateTime until, DateTime now) => throw ApiError(
    ApiErrorCode.rateLimited,
    'Too many attempts.',
    retryAfter: max(1, (until.difference(now).inMilliseconds / 1000).ceil()),
  );

  /// One transaction: a locked ip key is refused before any insert; rows locked in sorted key order;
  /// any locked key → 429 and the transaction rolls back (nothing counted); else each count + 1,
  /// the count reaching the max locks the key for its lock time, and an acct: key is locked for its delay.
  Future<void> hit(List<String> keys) async {
    final now = clock.now();
    final sorted = {...keys}.toList()..sort();
    final lockedKeys = <String>[];
    await db.transaction((tx) async {
      for (final k in sorted.where(
        (k) => k.startsWith('ip:') || k.startsWith('invite-ip:'),
      )) {
        final r = (await tx.query(
          'SELECT locked_until FROM login_attempts WHERE key = @k',
          {'k': k},
        )).firstOrNull;
        final until = _lockedUntil(r, now);
        if (until != null) _limited(until, now);
      }
      final rows = <String, Map<String, Object?>>{};
      for (final k in sorted) {
        // The no-op upsert takes the row lock.
        await tx.execute(
          'INSERT INTO login_attempts (key, count, window_start) VALUES (@k, 0, @now) '
          'ON CONFLICT (key) DO UPDATE SET count = login_attempts.count',
          {'k': k, 'now': iso(now)},
        );
        rows[k] = (await tx.query(
          'SELECT count, window_start, locked_until FROM login_attempts WHERE key = @k',
          {'k': k},
        )).single;
      }
      final locked = rows.values
          .map((r) => _lockedUntil(r, now))
          .whereType<DateTime>()
          .toList();
      if (locked.isNotEmpty) {
        _limited(locked.reduce((a, b) => a.isAfter(b) ? a : b), now);
      }
      for (final k in sorted) {
        final limit = _limitOf(k);
        final r = rows[k]!;
        final fresh = !parseIso(r['window_start']! as String)
            .add(limit.window)
            .isAfter(now);
        final count = fresh ? 1 : (r['count']! as int) + 1;
        final lock = limit.max == null
            // acct: the next attempt not before 1 s, 2 s, 4 s… 30 s.
            ? iso(now.add(Duration(seconds: min(30, 1 << min(count - 1, 5)))))
            : count >= limit.max!
            ? iso(now.add(limit.lock))
            : null;
        if (lock != null) lockedKeys.add(k);
        await tx.execute(
          'UPDATE login_attempts SET count = @c, window_start = @ws, locked_until = @lu WHERE key = @k',
          {
            'c': count,
            'ws': fresh ? iso(now) : r['window_start'],
            'lu': lock,
            'k': k,
          },
        );
      }
    });
    for (final k in lockedKeys) {
      if (k.startsWith('acct:') && k.contains('|ip:')) {
        onLockout?.call(k.substring(5, k.indexOf('|ip:')));
      }
    }
  }

  /// Lowers a count once; used for `invite-ip:` only, never for quotas.
  Future<void> refund(String key) => db.transaction(
    (tx) => tx.execute(
      'UPDATE login_attempts SET count = count - 1 WHERE key = @k AND count > 0',
      {'k': key},
    ),
  );

  Future<void> reset(List<String> keys) => db.transaction((tx) async {
    for (final k in keys) {
      await tx.execute('DELETE FROM login_attempts WHERE key = @k', {'k': k});
    }
  });
}
