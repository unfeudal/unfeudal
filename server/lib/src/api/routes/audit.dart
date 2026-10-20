// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../audit/visibility.dart';
import '../../db/db.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';

final _limit = RegExp(r'^\d{1,3}$');

/// One page of an audit view: a chain in seq order, or `me` and folder views by (ts, scope, seq).
Future<Response> getAudit(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final params = request.url.queryParameters;
  final scope = params['scope'] ?? 'me';
  final rawLimit = params['limit'] ?? '100';
  final limit = _limit.hasMatch(rawLimit) ? int.parse(rawLimit) : 0;
  if (limit < 1 || limit > 500) {
    throw ApiError.invalid('limit must be 1 to 500.');
  }
  AuditCursor? after;
  if (params['after'] case final text?) {
    try {
      after = AuditCursor.decode(text);
    } on FormatException {
      throw ApiError.invalid('after is not a cursor.');
    }
  }
  final page = await deps.db.transaction(readOnly: true, (tx) async {
    final query = await resolveAuditQuery(tx, auth, scope);
    return _page(tx, query, after, limit);
  });
  return jsonResponse({
    'events': [for (final e in page.events) e.toJson()],
    'next': page.next?.encode(),
  });
}

// ponytail: the folder view scans its org chain in Dart; index the targets if folder views of large orgs get slow
Future<({List<AuditEvent> events, AuditCursor? next})> _page(
  Tx tx,
  AuditQuery q,
  AuditCursor? after,
  int limit,
) async {
  final keyset = q.chainOrder
      ? 'e.seq > @q'
      : '(e.ts > @t OR (e.ts = @t AND (e.scope > @cs OR (e.scope = @cs AND e.seq > @q))))';
  final sql =
      'SELECT e.*${q.rawIps ? ', i.ip AS raw_ip' : ''} FROM audit_events e'
      '${q.rawIps ? ' LEFT JOIN audit_ips i ON i.scope = e.scope AND i.seq = e.seq' : ''}'
      ' WHERE ${q.actor != null ? 'e.actor_user = @a' : 'e.scope = @s'}';
  final order = q.chainOrder ? 'e.seq' : 'e.ts, e.scope, e.seq';
  final out = <AuditEvent>[];
  var at = after;
  while (true) {
    // one round for chains and `me`; the folder view keeps reading until the page is full
    final rows = await tx.query(
      '$sql${at == null ? '' : ' AND $keyset'} ORDER BY $order LIMIT @n',
      {
        if (q.actor != null) 'a': q.actor else 's': q.scope,
        if (at != null) 'q': at.q,
        if (at != null && !q.chainOrder) ...{'t': at.t, 'cs': at.s},
        'n': limit + 1,
      },
    );
    for (final r in rows) {
      final e = eventOfRow(r, ipAddress: r['raw_ip'] as String?);
      at = AuditCursor(t: e.ts, s: e.scope, q: e.seq);
      if (q.targets == null || e.targetIds.any(q.targets!.contains)) out.add(e);
      if (out.length > limit) {
        final last = out[limit - 1];
        return (
          events: out.sublist(0, limit),
          next: AuditCursor(t: last.ts, s: last.scope, q: last.seq),
        );
      }
    }
    if (rows.length <= limit) return (events: out, next: null);
  }
}
