// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

final _random = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

/// 32 random bytes in base64url (43 characters).
String randomToken() => b64(randomBytes(32));

const _base32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 base32 of 16 random bytes, no padding: 26 characters.
String newSetupToken() {
  final out = StringBuffer();
  var acc = 0, bits = 0;
  for (final byte in randomBytes(16)) {
    acc = (acc << 8 | byte) & 0xffff;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_base32[(acc >> bits) & 31]);
    }
  }
  if (bits > 0) out.write(_base32[(acc << (5 - bits)) & 31]);
  return out.toString();
}

/// Groups of 4 joined by `-`, for display; [normalizeSetupToken] reverts it.
String groupSetupToken(String t) =>
    [for (var i = 0; i < t.length; i += 4) t.substring(i, min(i + 4, t.length))]
        .join('-');
