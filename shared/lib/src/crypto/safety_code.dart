// SPDX-License-Identifier: Apache-2.0
import 'package:crypto/crypto.dart';

/// Six groups of 5 digits from SHA-256 of the key (≈ 99.6 bits), compared aloud between members.
String safetyCode(List<int> x25519PublicKey) {
  if (x25519PublicKey.length != 32) {
    throw ArgumentError('public key must be 32 bytes');
  }
  final h = sha256.convert(x25519PublicKey).bytes;
  return [
    for (var i = 0; i < 6; i++)
      (h.sublist(5 * i, 5 * i + 5).fold<int>(0, (acc, b) => acc * 256 + b) %
              100000)
          .toString()
          .padLeft(5, '0'),
  ].join(' ');
}

/// First 20 bytes of SHA-256, 40 lowercase hex characters.
String keyFingerprint(List<int> publicKey) {
  if (publicKey.length != 32) {
    throw ArgumentError('public key must be 32 bytes');
  }
  return '${sha256.convert(publicKey)}'.substring(0, 40);
}
