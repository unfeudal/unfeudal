// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/retention.dart';
import '../../orgs/org_access.dart';
import '../app.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// The server values and the org's own (null when unset), for the org settings screen.
Future<Response> getRetention(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final id = parseUuid(request.params['id']!);
  final settings = await deps.db.transaction(readOnly: true, (tx) async {
    await requireMember(tx, id, auth.userId, admin: true);
    final row = (await tx.query('SELECT settings FROM orgs WHERE id = @o', {
      'o': id,
    })).single;
    return jsonDecode(row['settings']! as String) as Map<String, Object?>;
  });
  final server = serverRetention(deps.config);
  return jsonResponse({
    'server': server,
    'org': {for (final key in server.keys) key: settings[key]},
  });
}
