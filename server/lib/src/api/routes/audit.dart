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

Future<({List<AuditEvent> events, AuditCursor? next})> _page(
  Tx tx,
  AuditQuery q,
  AuditCursor? after,
  int limit,
) async {
  final params = <String, Object?>{
    if (q.actor != null) 'a': q.actor else 's': q.scope,
    if (after != null) 'q': after.q,
    if (after != null && !q.chainOrder) ...{'t': after.t, 'cs': after.s},
    'n': limit + 1,
  };
  final keyset = q.chainOrder
      ? 'e.seq > @q'
      : '(e.ts > @t OR (e.ts = @t AND (e.scope > @cs OR (e.scope = @cs AND e.seq > @q))))';
  final rows = await tx.query(
    'SELECT e.*${q.rawIps ? ', i.ip AS raw_ip' : ''} FROM audit_events e'
    '${q.rawIps ? ' LEFT JOIN audit_ips i ON i.scope = e.scope AND i.seq = e.seq' : ''}'
    ' WHERE ${q.actor != null ? 'e.actor_user = @a' : 'e.scope = @s'}'
    '${_inFolders(q, params)}${after == null ? '' : ' AND $keyset'}'
    ' ORDER BY ${q.chainOrder ? 'e.seq' : 'e.ts, e.scope, e.seq'} LIMIT @n',
    params,
  );
  final events = [
    for (final r in rows) eventOfRow(r, ipAddress: r['raw_ip'] as String?),
  ];
  if (events.length <= limit) return (events: events, next: null);
  final last = events[limit - 1];
  return (
    events: events.sublist(0, limit),
    next: AuditCursor(t: last.ts, s: last.scope, q: last.seq),
  );
}

// The folder view's filter: an event naming a folder of the subtree or an item in one, through the
// audit_targets index rather than a scan of the org chain.
String _inFolders(AuditQuery q, Map<String, Object?> params) {
  final folders = q.folders;
  if (folders == null) return '';
  params['o'] = AuditScope(q.scope!).orgId;
  final names = <String>[];
  for (final (i, f) in folders.indexed) {
    params['f$i'] = f;
    names.add('@f$i');
  }
  final list = '(${names.join(', ')})';
  return ' AND EXISTS (SELECT 1 FROM audit_targets t WHERE t.scope = e.scope AND t.seq = e.seq AND '
      '(t.target_id IN $list OR t.target_id IN '
      '(SELECT id FROM items WHERE org_id = @o AND folder_id IN $list)))';
}
