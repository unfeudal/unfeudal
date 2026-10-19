// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../api/middleware.dart';
import '../db/db.dart';
import '../orgs/org_access.dart';

class AuditQuery {
  const AuditQuery({
    this.scope,
    this.actor,
    this.targets,
    required this.rawIps,
  });
  final String? scope; // one chain, or the org chain a folder view filters
  final String? actor; // `me`
  final Set<String>? targets; // folder view: subtree folders and their items
  final bool rawIps; // Instance Owner only
  bool get chainOrder => actor == null && targets == null;
}

Future<AuditQuery> resolveAuditQuery(
  Tx tx,
  AuthContext auth,
  String scope,
) async {
  final io = auth.isInstanceOwner;
  if (scope == 'me') return AuditQuery(actor: auth.userId, rawIps: io);
  if (scope == 'user') {
    return AuditQuery(scope: 'user:${auth.userId}', rawIps: io);
  }
  if (scope == 'instance') {
    if (!io) throw ApiError(ApiErrorCode.forbidden, 'Instance Owner only.');
    return const AuditQuery(scope: 'instance', rawIps: true);
  }
  final m = RegExp(r'^(org|folder):(.*)$').firstMatch(scope);
  if (m == null || !isUuid(m[2]!)) {
    throw ApiError(ApiErrorCode.invalidRequest, 'Unknown scope.');
  }
  final id = m[2]!;
  if (m[1] == 'org') {
    if ((await tx.query('SELECT 1 AS x FROM orgs WHERE id = @o', {
      'o': id,
    })).isEmpty) {
      // a deleted org's chain: Instance Owner only
      if (!io) throw ApiError.notFound();
      return AuditQuery(scope: 'org:$id', rawIps: true);
    }
    await requireMember(
      tx,
      id,
      auth.userId,
      admin: true,
    ); // not a confirmed member → 404, not admin → 403
    return AuditQuery(scope: 'org:$id', rawIps: io);
  }
  final orgId = await liveOrgFolder(tx, id);
  await requireMember(tx, orgId, auth.userId); // 404
  final org = (await loadOrg(tx, orgId))!;
  if (!permissionsOf(org, auth.userId, id).contains(Permission.manage)) {
    throw ApiError(ApiErrorCode.forbidden, 'You need manage on this folder.');
  }
  final folders = org.subtree(id).toSet();
  final items = await tx.query(
    'SELECT id, folder_id FROM items WHERE org_id = @o',
    {'o': orgId},
  );
  return AuditQuery(
    scope: 'org:$orgId',
    rawIps: io,
    targets: {
      ...folders,
      for (final r in items)
        if (folders.contains(r['folder_id'])) r['id']! as String,
    },
  );
}
