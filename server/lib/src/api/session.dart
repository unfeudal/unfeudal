// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../audit/audit_log.dart';
import '../db/db.dart';
import 'app.dart';
import 'validate.dart';

/// The new user's id; the secrets arrive already hashed (Argon2 runs before the transaction).
Future<String> insertUser(
  Tx tx,
  AppDeps deps, {
  required String email,
  required Object? bundle,
  required String authHash,
  required String recoveryHash,
  required String locale,
  required bool isInstanceOwner,
}) async {
  final userId = newId();
  await tx.execute(
    'INSERT INTO users (id, email, is_instance_owner, bundle, bundle_version, auth_hash, '
    'recovery_auth_hash, created_at, locale) '
    'VALUES (@id, @email, @owner, @bundle, 0, @auth, @recovery, @now, @locale)',
    {
      'id': userId,
      'email': email,
      'owner': isInstanceOwner,
      'bundle': jsonEncode(bundle),
      'auth': authHash,
      'recovery': recoveryHash,
      'now': iso(deps.clock.now()),
      'locale': locale,
    },
  );
  return userId;
}

/// A new device, audited as `device.added`, with its first refresh and access tokens;
/// the bundle is returned as stored.
Future<Session> createSession(
  Request request,
  Tx tx, {
  required String userId,
  required bool isInstanceOwner,
  required Map<String, Object?> bundle,
  required int bundleVersion,
  required DeviceInput device,
}) async {
  final deps = depsOf(request);
  final deviceId = newId();
  final now = iso(deps.clock.now());
  await tx.execute(
    'INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) '
    'VALUES (@id, @u, @name, @platform, @now, @now)',
    {
      'id': deviceId,
      'u': userId,
      'name': device.name,
      'platform': device.platform,
      'now': now,
    },
  );
  final refreshToken = await deps.refresh.create(tx, deviceId);
  await auditWriter(request, tx, actor: (user: userId, device: deviceId))(
    AuditScope.user(userId),
    'device.added',
    [deviceId],
  );
  return Session(
    userId: userId,
    deviceId: deviceId,
    accessToken: deps.access.issue(userId, deviceId),
    refreshToken: refreshToken,
    bundle: AccountBundle.fromJson(bundle),
    bundleVersion: bundleVersion,
    isInstanceOwner: isInstanceOwner,
  );
}

const _touchEvery = Duration(minutes: 5);

/// [lastSeenAt] (ISO, as stored) is old enough for [touchDevice] to write.
bool isTouchDue(String lastSeenAt, DateTime now) =>
    lastSeenAt.compareTo(iso(now.subtract(_touchEvery))) < 0;

/// Writes `last_seen_at` at most every 5 minutes per device.
Future<void> touchDevice(Tx tx, String deviceId, DateTime now) => tx.execute(
  'UPDATE devices SET last_seen_at = @now WHERE id = @d AND last_seen_at < @cutoff',
  {'now': iso(now), 'd': deviceId, 'cutoff': iso(now.subtract(_touchEvery))},
);
