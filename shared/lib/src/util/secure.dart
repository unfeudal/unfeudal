// SPDX-License-Identifier: Apache-2.0
import 'dart:math';
import 'dart:typed_data';

final _random = Random.secure();

Uint8List secureBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

/// Time depends on the length only, never on where the bytes differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
