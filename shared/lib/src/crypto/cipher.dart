// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../util/secure.dart';
import 'envelope.dart';
import 'errors.dart';

/// XChaCha20-Poly1305 with a random 24-byte nonce per encryption.
abstract final class SymmetricCipher {
  static final _aead = Xchacha20.poly1305Aead();

  static Uint8List newKey() => secureBytes(32);

  // Effective AAD is utf8(keyId), then a 0x00 byte, then aad: an envelope cannot be relabelled to another key.
  static List<int> _aad(String keyId, List<int> aad) => [
    ...utf8.encode(keyId),
    0,
    ...aad,
  ];

  static Future<Envelope> encrypt(
    List<int> key,
    List<int> plaintext,
    String keyId, {
    List<int> aad = const [],
  }) async {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'must be 32 bytes');
    }
    final nonce = secureBytes(24);
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _aad(keyId, aad),
    );
    return Envelope(
      v: 1,
      alg: Envelope.xchacha,
      keyId: keyId,
      nonce: nonce,
      ct: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  static Future<Uint8List> decrypt(
    List<int> key,
    Envelope envelope, {
    List<int> aad = const [],
  }) async {
    if (!envelope.isSupported) {
      throw UnsupportedEnvelope('envelope v${envelope.v} ${envelope.alg}');
    }
    final ct = envelope.ct;
    if (key.length != 32 || envelope.nonce.length != 24 || ct.length < 16) {
      throw const DecryptionFailed();
    }
    final box = SecretBox(
      ct.sublist(0, ct.length - 16),
      nonce: envelope.nonce,
      mac: Mac(ct.sublist(ct.length - 16)),
    );
    try {
      return Uint8List.fromList(
        await _aead.decrypt(
          box,
          secretKey: SecretKey(key),
          aad: _aad(envelope.keyId, aad),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const DecryptionFailed();
    }
  }
}
