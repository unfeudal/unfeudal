// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('isUuid accepts lowercase v4 only', () {
    expect(isUuid('6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20'), isTrue);
    expect(
      uuidPattern.hasMatch('6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20'),
      isTrue,
    );
    for (final s in [
      '6F1C2B9A-3D4E-4F50-8A61-7B8C9D0E1F20',
      '6f1c2b9a-3d4e-1f50-8a61-7b8c9d0e1f20',
      '6f1c2b9a-3d4e-4f50-7a61-7b8c9d0e1f20',
      '6f1c2b9a3d4e4f508a617b8c9d0e1f20',
      '',
    ]) {
      expect(isUuid(s), isFalse, reason: s);
    }
  });

  test('newId is a fresh v4 UUID', () {
    final ids = {for (var i = 0; i < 100; i++) newId()};
    expect(ids.length, 100);
    expect(ids.every(isUuid), isTrue);
  });
}
