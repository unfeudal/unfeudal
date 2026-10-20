// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../orgs/org_block.dart';
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
  final (rows, block) = await deps.db.transaction(readOnly: true, (tx) async {
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
        extra: {'reason': ConflictReason.cursorAhead.wire},
      );
    }
    final personal = [
      for (final r in await tx.query(
        'SELECT seq, body FROM items WHERE owner_user_id = @u AND seq > @c ORDER BY seq LIMIT 501',
        {'u': auth.userId, 'c': cursor},
      ))
        (seq: r['seq']! as int, body: r['body']! as String),
    ];
    if (!orgsOn) return (personal, null);
    // the same rows as one UNION ALL … ORDER BY seq LIMIT 501
    final merged = [
      ...personal,
      for (final r in await visibleOrgItems(
        tx,
        auth.userId,
        cursor,
        limit: 501,
      ))
        (seq: r.seq, body: r.body!),
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    final block = counters['org_seq']! > orgCursor
        ? await buildOrgBlock(tx, auth.userId)
        : null;
    return (merged.take(501).toList(), block);
  });
  final page = rows.take(500).toList();
  // A separate write: the snapshot above is read-only.
  await deps.db.transaction(
    (tx) => touchDevice(tx, auth.deviceId, deps.clock.now()),
  );
  return jsonResponse({
    'items': [for (final r in page) jsonDecode(r.body)],
    'cursor': page.isEmpty ? cursor : page.last.seq,
    'more': rows.length > 500,
    if (block != null) 'org': block.toJson(),
  });
}
