// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';

void main() {
  test('the operations doc covers every CLI command and example file', () {
    final ops = File('../docs/operations.md').readAsStringSync();
    for (final word in [
      'healthcheck',
      'backup',
      'new-epoch',
      'transfer-owner',
      'pg_dump',
      'config.example.yaml',
      'Caddyfile.example',
      'docker-compose.yml',
      'secret.key',
    ]) {
      expect(ops, contains(word), reason: word);
    }
  });

  test('the README links the source and the operations doc', () {
    final source = Config.load(const {
      'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
    }).sourceUrl.toString();
    expect(
      File('../README.md').readAsStringSync(),
      allOf(contains(source), contains('docs/operations.md')),
    );
  });

  test('every CHANGELOG starts with an Unreleased section', () {
    for (final pkg in ['server', 'client']) {
      expect(
        File('../$pkg/CHANGELOG.md').readAsStringSync(),
        startsWith('# Changelog\n\n## [Unreleased]\n'),
        reason: pkg,
      );
    }
  });

  test('the community files exist', () {
    for (final f in [
      'CONTRIBUTING.md',
      'SECURITY.md',
      'CODE_OF_CONDUCT.md',
      '.github/pull_request_template.md',
      '.github/ISSUE_TEMPLATE/bug.yml',
      '.github/ISSUE_TEMPLATE/feature.yml',
      '.github/ISSUE_TEMPLATE/config.yml',
    ]) {
      expect(File('../$f').existsSync(), isTrue, reason: f);
    }
    expect(File('../CONTRIBUTING.md').readAsStringSync(), contains('D.6'));
  });

  test('the release doc covers every kind of release', () {
    final release = File('../docs/release.md').readAsStringSync();
    for (final word in [
      'Prepare release',
      'patch',
      'minor',
      'security advisory',
      '1.0.0',
      'Gitea',
      'attestation',
    ]) {
      expect(release, contains(word), reason: word);
    }
  });
}
