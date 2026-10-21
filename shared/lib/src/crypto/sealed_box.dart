// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../bytes.dart';
import '../util/secure.dart';
import 'cipher.dart';
import 'envelope.dart';
import 'errors.dart';
import 'kdf.dart';

/// Anonymous-sender encryption to an X25519 public key. Authenticity comes
/// from member pins and key continuity, never from the box.
abstract final class SealedBox {
  static final _x25519 = X25519();

  static Future<Envelope> seal(
    List<int> bytes,
    List<int> recipientPublicKey,
    String purpose,
  ) async {
    if (recipientPublicKey.length != 32) {
      throw ArgumentError('recipient public key must be 32 bytes');
    }
    final ephemeral = await _x25519.newKeyPairFromSeed(secureBytes(32));
    final ephemeralPublicKey = (await ephemeral.extractPublicKey()).bytes;
    final key = await _key(
      ephemeral,
      recipientPublicKey,
      ephemeralPublicKey: ephemeralPublicKey,
      recipientPublicKey: recipientPublicKey,
      purpose: purpose,
    );
    final inner = await SymmetricCipher.encrypt(
      key,
      bytes,
      KeyIds.sealed(purpose),
    );
    return Envelope(
      v: 1,
      alg: Envelope.xchacha,
      keyId: inner.keyId,
      nonce: inner.nonce,
      ct: Uint8List.fromList([...ephemeralPublicKey, ...inner.ct]),
    );
  }

  static Future<Uint8List> open(
    Envelope envelope,
    SimpleKeyPair keyPair,
    String purpose,
  ) async {
    if (envelope.keyId != KeyIds.sealed(purpose)) {
      throw KeyLabelMismatch(envelope.keyId);
    }
    if (!envelope.isSupported) {
      throw UnsupportedEnvelope('envelope v${envelope.v} ${envelope.alg}');
    }
    if (envelope.ct.length < 32 + Envelope.tagLength) {
      throw const DecryptionFailed();
    }
    final ephemeralPublicKey = envelope.ct.sublist(0, 32);
    final ownPublicKey = (await keyPair.extractPublicKey()).bytes;
    final key = await _key(
      keyPair,
      ephemeralPublicKey,
      ephemeralPublicKey: ephemeralPublicKey,
      recipientPublicKey: ownPublicKey,
      purpose: purpose,
    );
    return SymmetricCipher.decrypt(
      key,
      Envelope(
        v: 1,
        alg: Envelope.xchacha,
        keyId: envelope.keyId,
        nonce: envelope.nonce,
        ct: envelope.ct.sublist(32),
      ),
    );
  }

  // key = hkdf32(X25519, `unfeudal/sealed/v1|<purpose>|<b64 ephemeralPublicKey>|<b64 recipientPublicKey>`); all-zero X25519 refused.
  static Future<Uint8List> _key(
    SimpleKeyPair mine,
    List<int> theirs, {
    required List<int> ephemeralPublicKey,
    required List<int> recipientPublicKey,
    required String purpose,
  }) async {
    final shared = await (await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
    )).extractBytes();
    if (shared.every((b) => b == 0)) throw const DecryptionFailed();
    return hkdf32(
      shared,
      'unfeudal/sealed/v1|$purpose|${b64(ephemeralPublicKey)}|${b64(recipientPublicKey)}',
    );
  }
}
