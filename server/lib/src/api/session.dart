// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../db/db.dart';

/// Writes `last_seen_at` at most every 5 minutes per device.
Future<void> touchDevice(Tx tx, String deviceId, DateTime now) => tx.execute(
  'UPDATE devices SET last_seen_at = @now WHERE id = @d AND last_seen_at < @cutoff',
  {
    'now': iso(now),
    'd': deviceId,
    'cutoff': iso(now.subtract(const Duration(minutes: 5))),
  },
);
