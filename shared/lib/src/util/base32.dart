// SPDX-License-Identifier: Apache-2.0
import 'dart:math';

/// RFC 4648 base32 alphabet.
const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 base32 without padding; the trailing bits are zero.
String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var acc = 0, bits = 0;
  for (final byte in bytes) {
    acc = (acc << 8 | byte) & 0xffff;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(base32Alphabet[(acc >> bits) & 31]);
    }
  }
  if (bits > 0) out.write(base32Alphabet[(acc << (5 - bits)) & 31]);
  return out.toString();
}

/// Groups of 4 characters joined by `-`, for display.
String groupBy4(String s) =>
    [for (var i = 0; i < s.length; i += 4) s.substring(i, min(i + 4, s.length))]
        .join('-');
