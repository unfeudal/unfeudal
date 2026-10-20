// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/rate_limit.dart';
import '../../db/db.dart';
import '../../orgs/org_access.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../request_audit.dart';

const _ssh = {
  'open': 'ssh.session_opened',
  'close': 'ssh.session_closed',
  'forward_start': 'ssh.forward_started',
  'forward_stop': 'ssh.forward_stopped',
};
String _id(Object? v) =>
    v is String && isUuid(v) ? v : throw ApiError.invalid('Malformed id.');

// Returns the audit scope and folder of a live item the caller holds [need]
// on. Anything else is 404, never 403, so item ids do not leak.
Future<(AuditScope, String?)> _usable(
  Tx tx,
  AppDeps deps,
  AuthContext auth,
  String id,
  Permission need,
  Map<String, OrgSnapshot?> orgs,
) async {
  final r =
      (await tx.query(
        'SELECT owner_user_id, org_id, folder_id, type FROM items WHERE id = @i AND deleted = 0 AND purged = 0',
        {'i': id},
      )).firstOrNull ??
      (throw ApiError.notFound());
  final (orgId, folderId) = (r['org_id'] as String?, r['folder_id'] as String?);
  if (orgId != null && !deps.features.enabled(Flag.orgs)) {
    throw ApiError.notFound();
  }
  await requireItemAccess(
    tx,
    r,
    itemId: id,
    userId: auth.userId,
    need: need,
    orgs: orgs,
  );
  return (
    orgId == null ? AuditScope.user(auth.userId) : AuditScope.org(orgId),
    folderId,
  );
}

Future<Response> sshEvent(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  // Counted before the body is read, and never refunded.
  await deps.limiter.hit([eventsKey(auth.userId)]);
  final body = await readJson(request);
  final action =
      _ssh[body['event']] ?? (throw ApiError.invalid('Unknown event.'));
  final host = _id(body['hostItemId']);
  final rawJumps = body['jumpHostItemIds'] ?? const [];
  if (rawJumps is! List || rawJumps.length > 8) {
    throw ApiError.invalid('At most 8 jump hosts.');
  }
  final jumps = [for (final j in rawJumps) _id(j)];
  final forward =
      action == 'ssh.forward_started' || action == 'ssh.forward_stopped';
  final port = body['localPort'];
  if (forward && (port is! int || port < 1 || port > 65535)) {
    throw ApiError.invalid('localPort must be 1-65535.');
  }
  await deps.db.transaction((tx) async {
    final orgs = <String, OrgSnapshot?>{};
    final (scope, _) = await _usable(
      tx,
      deps,
      auth,
      host,
      Permission.connect,
      orgs,
    );
    final targets = [host];
    for (final j in jumps) {
      final (jumpScope, _) = await _usable(
        tx,
        deps,
        auth,
        j,
        Permission.connect,
        orgs,
      );
      if (jumpScope.wire == scope.wire) {
        targets.add(j); // a jump host of another scope is checked, not recorded
      }
    }
    await auditWriter(request, tx)(scope, action, [
      ...targets,
      if (forward) 'forward:$port',
    ]);
  });
  return noContent();
}

Future<Response> revealEvent(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  await deps.limiter.hit([eventsKey(auth.userId)]);
  final id = _id((await readJson(request))['itemId']);
  await deps.db.transaction((tx) async {
    final (scope, folderId) = await _usable(
      tx,
      deps,
      auth,
      id,
      Permission.reveal,
      {},
    );
    await auditWriter(request, tx)(scope, 'item.revealed', [id, ?folderId]);
  });
  return noContent();
}
