// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../orgs/org_access.dart';
import '../app.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// The server values and the org's own (null when unset), for the org settings screen.
Future<Response> getRetention(Request request, String id) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(id); // 1.
  final settings = await deps.db.transaction(readOnly: true, (tx) async {
    await requireMember(tx, id, auth.userId, admin: true); // 2.
    final row = (await tx.query('SELECT settings FROM orgs WHERE id = @o', {
      'o': id,
    })).single;
    return jsonDecode(row['settings']! as String) as Map<String, Object?>;
  });
  final config = deps.config;
  return jsonResponse({
    'server': {
      'auditDays': config.auditRetentionDays,
      'maxVersions': config.itemHistoryMaxVersions,
      'trashDays': config.trashRetentionDays,
    },
    'org': {
      for (final key in ['auditDays', 'maxVersions', 'trashDays'])
        key: settings[key],
    },
  });
}
