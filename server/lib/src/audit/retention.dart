// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/deps.dart';
import '../db/db.dart';
import '../db/deletion.dart';
import '../db/maintenance.dart';
import '../items/item_write.dart';
import 'audit_log.dart';
import 'retention_policy.dart';

/// Runs the job now, then every 24 h until the returned timer is cancelled.
Timer startRetentionTimer(AppDeps deps) {
  unawaited(runRetention(deps));
  return Timer.periodic(
    const Duration(hours: 24),
    (_) => unawaited(runRetention(deps)),
  );
}

/// The daily retention steps, in order. Each step runs in its own try: a failure is logged and the next step runs.
/// Never throws.
Future<void> runRetention(AppDeps deps) async {
  for (final (name, step) in [
    ('audit', _audit),
    ('ips', _ips),
    ('revisions', _revisions),
    ('trash', _trash),
    ('cleanup', _cleanup),
  ]) {
    try {
      await step(deps);
    } on Object catch (e) {
      // Any failure is caught so one broken step never stops the others.
      deps.log.error('retention step failed', {
        'step': name,
        'type': '${e.runtimeType}',
      });
    }
  }
  deps.log.info('retention done');
}

Future<void> _audit(AppDeps deps) async {
  if (!deps.features.enabled(Flag.audit)) {
    return; // its checkpoint could not be written
  }
  final now = deps.clock.now();
  for (final r in await deps.db.query(
    'SELECT scope FROM audit_heads ORDER BY scope',
  )) {
    final scope = r['scope']! as String;
    await deps.db.transaction((tx) async {
      final days = (await retentionFor(
        tx,
        deps.config,
        AuditScope(scope).orgId,
      )).auditDays;
      if (days == 0) return; // forever
      final newest = (await tx.query(
        'SELECT seq, hash FROM audit_events WHERE scope = @s AND ts < @c ORDER BY seq DESC LIMIT 1',
        {'s': scope, 'c': iso(now.subtract(Duration(days: days)))},
      )).firstOrNull;
      if (newest == null) return;
      final p = {'s': scope, 'n': newest['seq']};
      await tx.execute(
        'DELETE FROM audit_ips WHERE scope = @s AND seq <= @n',
        p,
      );
      await tx.execute(
        'DELETE FROM audit_events WHERE scope = @s AND seq <= @n',
        p,
      );
      // The head row stays, so the chain continues from this checkpoint.
      await deps.audit.append(
        tx,
        scope: AuditScope(scope),
        action: 'audit.checkpoint',
        targetIds: ['seq:${newest['seq']}', 'hash:${newest['hash']}'],
      );
    });
  }
}

// Deletes raw addresses older than audit_ip_retention_days; the events and their pseudonyms stay.
Future<void> _ips(AppDeps deps) async {
  final cutoff = deps.clock.now().subtract(
    Duration(days: deps.config.auditIpRetentionDays),
  );
  await deps.db.execute(
    'DELETE FROM audit_ips WHERE EXISTS (SELECT 1 FROM audit_events e '
    'WHERE e.scope = audit_ips.scope AND e.seq = audit_ips.seq AND e.ts < @c)',
    {'c': iso(cutoff)},
  );
}

// Prunes revisions beyond each item's effective maxVersions.
Future<void> _revisions(AppDeps deps) async {
  for (final r in await deps.db.query(
    'SELECT DISTINCT r.item_id, i.org_id FROM item_revisions r JOIN items i ON i.id = r.item_id',
  )) {
    await deps.db.transaction((tx) async {
      final max = (await retentionFor(
        tx,
        deps.config,
        r['org_id'] as String?,
      )).maxVersions;
      await pruneRevisions(tx, r['item_id']! as String, max);
    });
  }
}

// Purges trashed items past their scope's effective trashDays (0: never), one transaction each.
Future<void> _trash(AppDeps deps) async {
  final now = deps.clock.now();
  final groups = <(String, int, Map<String, Object?>)>[
    ('owner_user_id IS NOT NULL', deps.config.trashRetentionDays, {}),
  ];
  for (final r in await deps.db.query('SELECT id FROM orgs ORDER BY id')) {
    final orgId = r['id']! as String;
    final days = (await deps.db.transaction(
      readOnly: true,
      (tx) => retentionFor(tx, deps.config, orgId),
    )).trashDays;
    groups.add(('org_id = @o', days, {'o': orgId}));
  }
  for (final (where, days, params) in groups) {
    if (days == 0) continue; // never purged
    final due = await deps.db.query(
      'SELECT id FROM items WHERE deleted = 1 AND purged = 0 AND updated_at < @cutoff AND $where ORDER BY updated_at',
      {...params, 'cutoff': iso(now.subtract(Duration(days: days)))},
    );
    // purgeItem re-checks purged, since the subtrees of due items overlap.
    for (final r in due) {
      await deps.db.transaction(
        (tx) => purgeItem(tx, r['id']! as String, deps.audit),
      );
    }
  }
}

// Deletes expired limiter windows, dead refresh tokens and stale invites; then SQLite hands freed pages back.
Future<void> _cleanup(AppDeps deps) async {
  await deps.db.transaction(
    (tx) => runCleanup(tx, deps.clock.now(), deps.config),
  );
  // outside the transaction: SQLite refuses incremental_vacuum inside one
  if (deps.db.engine == DbEngine.sqlite) {
    await deps.db.execute('PRAGMA incremental_vacuum');
  }
}
