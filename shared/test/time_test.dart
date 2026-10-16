// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('iso is 24 chars, UTC, milliseconds', () {
    final t = DateTime.utc(2026, 10, 13, 12, 0, 0, 7, 999);
    expect(iso(t), '2026-10-13T12:00:00.007Z');
    expect(iso(DateTime.utc(2026, 1, 2).toLocal()), '2026-01-02T00:00:00.000Z');
  });

  test('parseIso accepts only iso() output', () {
    expect(
      parseIso('2026-10-13T12:00:00.000Z'),
      DateTime.utc(2026, 10, 13, 12),
    );
    for (final s in [
      '2026-10-13T12:00:00Z',
      '2026-10-13T12:00:00.000+00:00',
      '2026-13-01T00:00:00.000Z',
      '2026-10-13 12:00:00.000Z',
      '',
    ]) {
      expect(() => parseIso(s), throwsFormatException, reason: s);
    }
  });
}
