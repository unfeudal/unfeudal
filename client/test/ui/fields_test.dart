// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/fields.dart';

void main() {
  test('password score: empty, short, then length and character classes', () {
    expect(passwordScore(''), 0);
    expect(passwordScore('abc'), 1);
    expect(passwordScore('abcdefgh'), 2);
    expect(passwordScore('abcdefghijkl'), 3);
    expect(passwordScore('Abcdefgh1jkl'), 4);
    expect(passwordScore('abcdefghijklmnop'), 4);
  });
}
