// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/tokens.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../request_audit.dart';
import '../validate.dart';

/// Own devices, revoked included, oldest first; the caller's device is `current`.
Future<Response> listDevices(Request request) async {
  final deps = depsOf(request);
  final auth = authOf(request);
  final rows = await deps.db.query(
    'SELECT id, name, platform, created_at, last_seen_at, revoked_at FROM devices '
    'WHERE user_id = @u ORDER BY created_at, id',
    {'u': auth.userId},
  );
  return jsonResponse({
    'devices': [
      for (final r in rows)
        Device(
          id: r['id']! as String,
          name: r['name']! as String,
          platform: r['platform']! as String,
          createdAt: parseIso(r['created_at']! as String),
          lastSeenAt: parseIso(r['last_seen_at']! as String),
          revokedAt: r['revoked_at'] == null
              ? null
              : parseIso(r['revoked_at']! as String),
          isCurrent: r['id'] == auth.deviceId,
        ).toJson(),
    ],
  });
}

/// Own devices only (another account's is 404); idempotent; its tokens stop working at once.
Future<Response> deleteDevice(Request request) async {
  final deps = depsOf(request);
  final auth = authOf(request);
  final id = parseUuid(request.params['id']!);
  await deps.db.transaction((tx) async {
    final rows = await tx.query(
      'SELECT id FROM devices WHERE id = @d AND user_id = @u',
      {'d': id, 'u': auth.userId},
    );
    if (rows.isEmpty) throw ApiError.notFound();
    await revokeDevice(tx, id, deps.clock.now());
    await auditWriter(request, tx)(
      AuditScope.user(auth.userId),
      'device.revoked',
      [id],
    );
  });
  return noContent();
}
