// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/migrations.dart';

/// Comments out, split on `;`, whitespace collapsed.
List<String> statementsOf(String sql) => sql
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'--.*$'), ''))
    .join('\n')
    .split(';')
    .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  test('every entry holds one statement per string', () {
    for (final m in migrations) {
      expect(m.statements, isNotEmpty, reason: 'v${m.version}');
      expect(
        m.statements.every((s) => statementsOf(s).length == 1),
        isTrue,
        reason: 'v${m.version}',
      );
    }
  });

  test('versions are 1..n in order', () {
    expect(migrations.map((m) => m.version), [
      for (var i = 1; i <= migrations.length; i++) i,
    ]);
  });
}
