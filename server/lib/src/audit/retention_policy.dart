// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../config/config.dart';
import '../db/db.dart';

typedef Retention = ({int auditDays, int maxVersions, int trashDays});

/// The server values, keyed as in org settings.
Map<String, int> serverRetention(Config config) => {
  'auditDays': config.auditRetentionDays,
  'maxVersions': config.itemHistoryMaxVersions,
  'trashDays': config.trashRetentionDays,
};

// An org may only shorten the server retention (36500 days at most when the
// server keeps forever); auditDays stays at 30 or more, unless the server is below 30.
void checkOrgRetention(String key, Object? value, int server) {
  if (value is! int) {
    throw ApiError.invalid('$key must be an integer or null.');
  }
  final ceiling = server == 0 ? 36500 : server;
  final floor = key == 'auditDays'
      ? (server != 0 && server < 30 ? server : 30)
      : 1;
  if (value < floor || value > ceiling) {
    throw ApiError.invalid('$key must be between $floor and $ceiling.');
  }
}

/// The org's settings column, decoded; empty when no org has [orgId].
Future<Map<String, Object?>> orgSettings(Tx tx, String orgId) async {
  final rows = await tx.query('SELECT settings FROM orgs WHERE id = @o', {
    'o': orgId,
  });
  return rows.isEmpty
      ? <String, Object?>{}
      : jsonDecode(rows.single['settings']! as String) as Map<String, Object?>;
}

/// The server values, each made stricter by the org's settings when [orgId] names an existing org.
Future<Retention> retentionFor(Tx tx, Config config, String? orgId) async {
  final settings = orgId == null
      ? const <String, Object?>{}
      : await orgSettings(tx, orgId);
  final server = serverRetention(config);
  int value(String key) =>
      effectiveRetention(server[key]!, settings[key] as int?);
  return (
    auditDays: value('auditDays'),
    maxVersions: value('maxVersions'),
    trashDays: value('trashDays'),
  );
}
