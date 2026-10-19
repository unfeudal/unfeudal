// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/rate_limit.dart';
import '../../config/features.dart';
import '../../db/db.dart';
import '../../orgs/org_access.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';

const _ssh = {
  'open': 'ssh.session_opened',
  'close': 'ssh.session_closed',
  'forward_start': 'ssh.forward_started',
  'forward_stop': 'ssh.forward_stopped',
};
ApiError _bad(String m) => ApiError(ApiErrorCode.invalidRequest, m);
String _id(Object? v) =>
    v is String && isUuid(v) ? v : throw _bad('Malformed id.');

/// Check 5 (ssh) / 4 (reveal): exists, not deleted, the caller's own personal item or an org item where the caller
/// holds [need] on its folder (a folder item: on itself) → its scope and folder. Anything else is 404, never 403.
Future<(AuditScope, String?)> _usable(
  Tx tx,
  AppDeps deps,
  AuthContext auth,
  String id,
  Permission need,
) async {
  final r =
      (await tx.query(
        'SELECT owner_user_id, org_id, folder_id, type FROM items WHERE id = @i AND deleted = 0 AND purged = 0',
        {'i': id},
      )).firstOrNull ??
      (throw ApiError.notFound());
  final (orgId, folderId) = (r['org_id'] as String?, r['folder_id'] as String?);
  if (orgId == null) {
    if (r['owner_user_id'] != auth.userId) throw ApiError.notFound();
    return (AuditScope.user(auth.userId), folderId);
  }
  if (!deps.features.enabled(Flag.orgs)) throw ApiError.notFound();
  final org = await loadOrg(tx, orgId) ?? (throw ApiError.notFound());
  if (!permissionsOf(
    org,
    auth.userId,
    r['type'] == 'folder' ? id : folderId!,
  ).contains(need)) {
    throw ApiError.notFound();
  }
  return (AuditScope.org(orgId), folderId);
}

Future<Response> sshEvent(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  await deps.limiter.hit([
    eventsKey(auth.userId),
  ]); // 2. before the body; never refunded
  final body = await readJson(request); // 3.
  final action = _ssh[body['event']] ?? (throw _bad('Unknown event.'));
  final host = _id(body['hostItemId']);
  final rawJumps = body['jumpHostItemIds'] ?? const [];
  if (rawJumps is! List || rawJumps.length > 8) {
    throw _bad('At most 8 jump hosts.');
  }
  final jumps = [for (final j in rawJumps) _id(j)];
  final forward =
      action == 'ssh.forward_started' || action == 'ssh.forward_stopped';
  final port = body['localPort'];
  if (forward && (port is! int || port < 1 || port > 65535)) {
    throw _bad('localPort must be 1–65535.'); // 4.
  }
  await deps.db.transaction((tx) async {
    final (scope, _) = await _usable(
      tx,
      deps,
      auth,
      host,
      Permission.connect,
    ); // 5.
    final targets = [host];
    for (final j in jumps) {
      final (jumpScope, _) = await _usable(
        tx,
        deps,
        auth,
        j,
        Permission.connect,
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
  await deps.limiter.hit([eventsKey(auth.userId)]); // 2.
  final id = _id((await readJson(request))['itemId']); // 3.
  await deps.db.transaction((tx) async {
    final (scope, folderId) = await _usable(
      tx,
      deps,
      auth,
      id,
      Permission.reveal,
    ); // 4.
    await auditWriter(request, tx)(scope, 'item.revealed', [id, ?folderId]);
  });
  return noContent();
}
