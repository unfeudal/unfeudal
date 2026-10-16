// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/config/features.dart';

void main() {
  final text = File('../config.example.yaml').readAsStringSync();

  test('documents every key and every flag', () {
    for (final key in Config.keys) {
      expect(
        text,
        contains(RegExp('^(# )?$key:', multiLine: true)),
        reason: key,
      );
    }
    for (final flag in Flag.values) {
      expect(
        text,
        contains(RegExp('^  (# )?${flag.wire}:', multiLine: true)),
        reason: flag.wire,
      );
    }
  });

  test('loads as is and its values are the defaults', () {
    final c = Config.load(const {}, yamlText: text);
    final d = Config.load(const {
      'UNFEUDAL_PUBLIC_URL': 'https://vault.example.org',
    });
    expect(c.publicUrl, Uri.parse('https://vault.example.org'));
    expect(
      (
        c.databaseUrl,
        c.listen,
        c.secretFile,
        c.sourceUrl,
        c.logLevel,
        c.timezone,
      ),
      (
        d.databaseUrl,
        d.listen,
        d.secretFile,
        d.sourceUrl,
        d.logLevel,
        d.timezone,
      ),
    );
    expect(
      (
        c.accessTokenTtl,
        c.refreshTokenTtl,
        c.loginMaxAttempts,
        c.loginLockout,
        c.inviteTtl,
      ),
      (
        d.accessTokenTtl,
        d.refreshTokenTtl,
        d.loginMaxAttempts,
        d.loginLockout,
        d.inviteTtl,
      ),
    );
    expect(
      (c.maxVaultSize, c.maxOrgSize, c.maxOrgsPerUser, c.maxDevicesPerUser),
      (d.maxVaultSize, d.maxOrgSize, d.maxOrgsPerUser, d.maxDevicesPerUser),
    );
    expect(
      (
        c.auditRetentionDays,
        c.auditIpRetentionDays,
        c.itemHistoryMaxVersions,
        c.trashRetentionDays,
      ),
      (
        d.auditRetentionDays,
        d.auditIpRetentionDays,
        d.itemHistoryMaxVersions,
        d.trashRetentionDays,
      ),
    );
    expect(
      (c.minClientVersion, c.orgCreation, c.smtp, c.setupToken),
      (d.minClientVersion, d.orgCreation, null, null),
    );
    for (final f in Flag.values) {
      expect(c.features.enabled(f), d.features.enabled(f), reason: f.wire);
    }
  });
}
