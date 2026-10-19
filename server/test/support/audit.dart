// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_server/src/audit/audit_log.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'test_server.dart';

/// Every stored event of [scope], chain order, with its raw IP.
Future<List<AuditEvent>> auditEvents(TestServer s, String scope) async => [
  for (final r in await s.db.query(
    'SELECT e.*, i.ip AS raw_ip FROM audit_events e '
    'LEFT JOIN audit_ips i ON i.scope = e.scope AND i.seq = e.seq WHERE e.scope = @s ORDER BY e.seq',
    {'s': scope},
  ))
    eventOfRow(r, ipAddress: r['raw_ip'] as String?),
];

/// `[action, ...targets]` per event of [scope], oldest first.
Future<List<List<String>>> actions(TestServer s, String scope) async => [
  for (final e in await auditEvents(s, scope)) [e.action, ...e.targetIds],
];
