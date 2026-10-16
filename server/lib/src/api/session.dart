// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../db/db.dart';
import 'app.dart';
import 'validate.dart';

/// A new device with its first refresh and access tokens; the bundle is returned as stored.
Future<Session> createSession(
  AppDeps deps,
  Tx tx, {
  required String userId,
  required bool isInstanceOwner,
  required Map<String, Object?> bundle,
  required int bundleVersion,
  required DeviceInput device,
}) async {
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

/// Writes `last_seen_at` at most every 5 minutes per device.
Future<void> touchDevice(Tx tx, String deviceId, DateTime now) => tx.execute(
  'UPDATE devices SET last_seen_at = @now WHERE id = @d AND last_seen_at < @cutoff',
  {
    'now': iso(now),
    'd': deviceId,
    'cutoff': iso(now.subtract(const Duration(minutes: 5))),
  },
);
