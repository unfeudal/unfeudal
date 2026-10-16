// SPDX-License-Identifier: Apache-2.0
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../util/secure.dart';
import 'errors.dart';
import 'kdf.dart';

abstract final class RecoveryKey {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List generate() => secureBytes(32);

  /// 32 bytes + SHA-256(key)[0] → base32 (no padding, trailing bits zero) → groups of 4 joined by '-'.
  static String encode(List<int> key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'must be 32 bytes');
    }
    final data = [...key, sha256.convert(key).bytes[0]];
    final out = StringBuffer();
    var acc = 0, bits = 0;
    for (final byte in data) {
      acc = (acc << 8 | byte) & 0xffff;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(acc >> bits) & 31]);
      }
    }
    if (bits > 0) out.write(_alphabet[(acc << (5 - bits)) & 31]);
    final s = out.toString(); // 53 chars
    return [
      for (var i = 0; i < s.length; i += 4)
        s.substring(i, min(i + 4, s.length)),
    ].join('-');
  }

  static Uint8List decode(String text) {
    final s = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (s.length != 53) throw const InvalidRecoveryKey();
    final out = <int>[];
    var acc = 0, bits = 0;
    for (final ch in s.split('')) {
      final v = _alphabet.indexOf(ch);
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
