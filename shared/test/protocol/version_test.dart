// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('versions are X.Y.Z compared numerically', () {
    expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
    expect(compareVersions('1.2.3', '1.2.3'), 0);
    expect(canonicalVersion('01.2.3'), '1.2.3');
    for (final s in [
      '1.2',
      '1.2.3-beta',
      '1.2.3+4',
      'v1.2.3',
      ' 1.2.3',
      '1.2.x',
      '1.2.${'3' * 30}',
      '',
    ]) {
      expect(() => canonicalVersion(s), throwsFormatException, reason: s);
    }
  });
}
