// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'db.dart';

const _touchEvery = Duration(minutes: 5);

/// [lastSeenAt] (ISO, as stored) is old enough for [touchDevice] to write.
bool isTouchDue(String lastSeenAt, DateTime now) =>
    lastSeenAt.compareTo(iso(now.subtract(_touchEvery))) < 0;

/// Writes `last_seen_at` at most every 5 minutes per device.
Future<void> touchDevice(Tx tx, String deviceId, DateTime now) => tx.execute(
  'UPDATE devices SET last_seen_at = @now WHERE id = @d AND last_seen_at < @cutoff',
  {'now': iso(now), 'd': deviceId, 'cutoff': iso(now.subtract(_touchEvery))},
);
