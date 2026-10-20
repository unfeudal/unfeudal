// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import '../db.dart';
import '../migration.dart';

const auditTargetsMigration = Migration(5, [
  r"""CREATE TABLE audit_targets (
  scope     TEXT NOT NULL,
  seq       BIGINT NOT NULL,
  target_id TEXT NOT NULL,
  PRIMARY KEY (scope, seq, target_id))""",
  r"""CREATE INDEX audit_targets_target ON audit_targets (scope, target_id)""",
], backfill: _indexEventTargets);

// Reads the events in pages: the JSON target lists of both engines are decoded the same way, in Dart.
Future<void> _indexEventTargets(Tx tx) async {
  var after = (scope: '', seq: -1);
  while (true) {
    final rows = await tx.query(
      'SELECT scope, seq, target_ids FROM audit_events '
      'WHERE scope > @s OR (scope = @s AND seq > @q) ORDER BY scope, seq LIMIT 500',
      {'s': after.scope, 'q': after.seq},
    );
    for (final r in rows) {
      after = (scope: r['scope']! as String, seq: r['seq']! as int);
      await _insertTargets(
        tx,
        scope: after.scope,
        seq: after.seq,
        targetIds: [
          for (final id
              in jsonDecode(r['target_ids']! as String) as List<Object?>)
            id! as String,
        ],
      );
    }
    if (rows.length < 500) return;
  }
}

// Kept here rather than shared with the audit log: a released migration never changes.
Future<void> _insertTargets(
  Tx tx, {
  required String scope,
  required int seq,
  required List<String> targetIds,
}) async {
  for (final id in targetIds.toSet()) {
    await tx.execute(
      'INSERT INTO audit_targets (scope, seq, target_id) VALUES (@s, @q, @t)',
      {'s': scope, 'q': seq, 't': id},
    );
  }
}
