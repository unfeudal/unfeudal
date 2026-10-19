// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../config/config.dart';
import '../db/db.dart';

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
