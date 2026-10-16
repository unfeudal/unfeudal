// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../config/features.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../session.dart';

final _cursor = RegExp(r'^\d{1,15}$');

int _cursorParam(Request request, String name) {
  final v = request.url.queryParameters[name];
  if (v == null) return 0;
  if (!_cursor.hasMatch(v)) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      '$name must be an integer ≥ 0.',
    );
  }
  return int.parse(v);
}

/// One page of item changes after `cursor`, trash and tombstones included,
/// read in one snapshot.
Future<Response> sync(Request request) async {
  final deps = depsOf(request);
  final auth = authOf(request);
  final cursor = _cursorParam(request, 'cursor');
  final orgCursor = _cursorParam(request, 'orgCursor');
  final orgsOn = deps.features.enabled(Flag.orgs);
  final rows = await deps.db.transaction(readOnly: true, (tx) async {
    final counters = {
      for (final r in await tx.query('SELECT name, value FROM counters'))
        r['name']: r['value']! as int,
    };
    // The server was restored behind this device: the client runs its restore flow.
    if (cursor > counters['items_seq']! ||
        (orgsOn && orgCursor > counters['org_seq']!)) {
      throw ApiError(
        ApiErrorCode.conflict,
        'The server is behind this device.',
        extra: {'reason': 'cursor_ahead'},
      );
    }
    // Org hook: memberships and loadOrg, UNION ALL of the org branch, org block when org_seq > orgCursor.
    return tx.query(
      'SELECT seq, body FROM items WHERE owner_user_id = @u AND seq > @c ORDER BY seq LIMIT 501',
      {'u': auth.userId, 'c': cursor},
    );
  });
  final page = rows.take(500).toList();
  // A separate write: the snapshot above is read-only.
  await deps.db.transaction(
    (tx) => touchDevice(tx, auth.deviceId, deps.clock.now()),
  );
  return jsonResponse({
    'items': [for (final r in page) jsonDecode(r['body']! as String)],
    'cursor': page.isEmpty ? cursor : page.last['seq'],
    'more': rows.length > 500,
  });
}
