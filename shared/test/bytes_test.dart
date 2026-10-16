// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('b64 is base64url without padding', () {
    expect(b64([0xfb, 0xff]), '-_8');
    expect(b64(List.filled(16, 0)), 'AAAAAAAAAAAAAAAAAAAAAA');
    expect(b64(const []), '');
  });

  test('unb64 accepts padding and round-trips', () {
    expect(unb64('-_8'), [0xfb, 0xff]);
    expect(unb64('-_8='), [0xfb, 0xff]);
    expect(unb64(''), isEmpty);
    final bytes = Uint8List.fromList(List.generate(33, (i) => i * 7 % 256));
    expect(unb64(b64(bytes)), bytes);
  });

  test('unb64 rejects other alphabets, bad lengths and non-canonical text', () {
    for (final s in ['+/8', 'ab c', 'A', 'AAAAA', 'AB', 'A===', '%%']) {
      expect(() => unb64(s), throwsFormatException, reason: s);
    }
  });
}
