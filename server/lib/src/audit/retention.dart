// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/app.dart';
import '../config/config.dart';
import '../config/features.dart';
import '../db/db.dart';
import '../items/item_write.dart';
import 'audit_log.dart';

typedef Retention = ({int auditDays, int maxVersions, int trashDays});

/// The server values, each made stricter by the org's settings when [orgId] names an existing org.
Future<Retention> retentionFor(Tx tx, Config config, String? orgId) async {
  final rows = orgId == null
      ? const <Map<String, Object?>>[]
      : await tx.query('SELECT settings FROM orgs WHERE id = @o', {'o': orgId});
  final settings = rows.isEmpty
      ? const <String, Object?>{}
      : jsonDecode(rows.single['settings']! as String) as Map<String, Object?>;
  int value(int server, String key) =>
      effectiveRetention(server, settings[key] as int?);
  return (
    auditDays: value(config.auditRetentionDays, 'auditDays'),
    maxVersions: value(config.itemHistoryMaxVersions, 'maxVersions'),
    trashDays: value(config.trashRetentionDays, 'trashDays'),
  );
}

/// The daily retention steps, in order. Each step runs in its own try: a failure is logged and the next step runs.
class RetentionJob {
  RetentionJob(this.deps);

  final AppDeps deps;

  /// Never throws.
  Future<void> runOnce() async {
    for (final (name, step) in [
      ('audit', _audit),
      ('ips', _ips),
      ('revisions', _revisions),
    ]) {
      try {
        await step();
      } catch (e) {
        deps.log.error('retention step failed', {
          'step': name,
          'type': '${e.runtimeType}',
        });
      }
    }
    deps.log.info('retention done');
  }

  Future<void> _audit() async {
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
          scope.startsWith('org:') ? scope.substring(4) : null,
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
        await deps.audit.append(
          tx,
          scope: AuditScope(scope),
          action: 'audit.checkpoint',
          targetIds: ['seq:${newest['seq']}', 'hash:${newest['hash']}'],
        ); // the head row stays: the chain continues
      });
    }
  }

  /// Raw addresses older than audit_ip_retention_days; the events and their pseudonyms stay.
  Future<void> _ips() async {
    final cutoff = deps.clock.now().subtract(
      Duration(days: deps.config.auditIpRetentionDays),
    );
    await deps.db.execute(
      'DELETE FROM audit_ips WHERE EXISTS (SELECT 1 FROM audit_events e '
      'WHERE e.scope = audit_ips.scope AND e.seq = audit_ips.seq AND e.ts < @c)',
      {'c': iso(cutoff)},
    );
  }

  /// Revisions beyond each item's effective maxVersions.
  Future<void> _revisions() async {
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
}
