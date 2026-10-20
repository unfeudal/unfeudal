// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../orgs/org_access.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// The current item then the stored versions, newest first; a purged item answers [].
Future<Response> listRevisions(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final id = parseUuid(request.params['id']!);
  final list = await deps.db.transaction(readOnly: true, (tx) async {
    final cur =
        (await tx.query(
          'SELECT owner_user_id, org_id, folder_id, type, purged, body FROM items WHERE id = @i',
          {'i': id},
        )).firstOrNull ??
        (throw ApiError.notFound());
    if (cur['org_id'] != null && !deps.features.enabled(Flag.orgs)) {
      throw ApiError.orgsOff();
    }
    // A personal item needs its owner, an org item needs view (admins hold every permission).
    await requireItemAccess(
      tx,
      cur,
      itemId: id,
      userId: auth.userId,
      need: Permission.view,
    );
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
