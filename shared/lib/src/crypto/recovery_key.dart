// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../util/base32.dart';
import '../util/secure.dart';
import 'errors.dart';
import 'kdf.dart';

abstract final class RecoveryKey {
  static Uint8List generate() => secureBytes(32);

  /// The 32 bytes followed by SHA-256(key)[0], in base32 (no padding, trailing bits zero),
  /// split into groups of 4 joined by '-'.
  static String encode(List<int> key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'must be 32 bytes');
    }
    return groupBy4(base32Encode([...key, sha256.convert(key).bytes[0]]));
  }

  static Uint8List decode(String text) {
    final s = ungroup(text);
    if (s.length != 53) throw const InvalidRecoveryKey();
    final out = <int>[];
    var acc = 0, bits = 0;
    for (final ch in s.split('')) {
      final v = base32Alphabet.indexOf(ch);
      if (v < 0) throw const InvalidRecoveryKey();
      acc = (acc << 5 | v) & 0xffff;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((acc >> bits) & 0xff);
      }
    }
    // Trailing bits must be zero, so each key has exactly one text form.
    if ((acc & ((1 << bits) - 1)) != 0) throw const InvalidRecoveryKey();
    final key = Uint8List.fromList(out.sublist(0, 32));
    if (sha256.convert(key).bytes[0] != out[32]) {
      throw const InvalidRecoveryKey();
    }
    return key;
  }
}

Future<Uint8List> recoveryAuthKey(List<int> recovery) =>
    hkdf32(recovery, 'unfeudal/recovery-auth/v1');

Future<Uint8List> recoveryWrapKey(List<int> recovery) =>
    hkdf32(recovery, 'unfeudal/recovery-wrap/v1');
