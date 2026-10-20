// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../orgs/org_access.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// The current item then the stored versions, newest first; a purged item answers [].
Future<Response> listRevisions(Request request) async {
  final id = request.params['id']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(id); // 2.
  final list = await deps.db.transaction(readOnly: true, (tx) async {
    final cur =
        (await tx.query(
          'SELECT owner_user_id, org_id, folder_id, type, purged, body FROM items WHERE id = @i',
          {'i': id},
        )).firstOrNull ??
        (throw ApiError.notFound()); // 3.
    final orgId = cur['org_id'] as String?;
    if (orgId == null) {
      if (cur['owner_user_id'] != auth.userId) throw ApiError.notFound(); // 4.
    } else {
      if (!deps.features.enabled(Flag.orgs)) {
        throw ApiError.orgsOff();
      }
      final org =
          await loadOrg(tx, orgId) ??
          (throw ApiError.notFound()); // 5. admins hold every permission
      final folder = cur['type'] == 'folder' ? id : cur['folder_id']! as String;
      if (!permissionsOf(org, auth.userId, folder).contains(Permission.view)) {
        throw ApiError.notFound();
      }
    }
    if (cur['purged'] == 1) return const <Object?>[];
    final older = await tx.query(
      'SELECT body FROM item_revisions WHERE item_id = @i ORDER BY revision DESC',
      {'i': id},
    );
    return [
      jsonDecode(cur['body']! as String),
      for (final r in older) jsonDecode(r['body']! as String),
    ];
  });
  return jsonResponse({'revisions': list});
}
