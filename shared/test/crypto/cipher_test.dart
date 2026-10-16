// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

Envelope relabel(
  Envelope e, {
  String? keyId,
  List<int>? nonce,
  List<int>? ct,
}) => Envelope(
  v: e.v,
  alg: e.alg,
  keyId: keyId ?? e.keyId,
  nonce: Uint8List.fromList(nonce ?? e.nonce),
  ct: Uint8List.fromList(ct ?? e.ct),
);

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));

  test('decrypts the known answer', () async {
    final e = Envelope.fromJson({
      'v': 1,
      'alg': 'xchacha20poly1305',
      'keyId': 'user',
      'nonce': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYX',
      'ct': '9qdjE__ue05iEFuFzwjfo1D79jxe',
    });
    expect(
      utf8.decode(
        await SymmetricCipher.decrypt(key, e, aad: utf8.encode('item-aad')),
      ),
      'hello',
    );
  });

  test('round-trips with a fresh 24-byte nonce each time', () async {
    final k = SymmetricCipher.newKey();
    expect(k.length, 32);
    final a = await SymmetricCipher.encrypt(k, [1, 2, 3], 'k', aad: [9]);
    final b = await SymmetricCipher.encrypt(k, [1, 2, 3], 'k', aad: [9]);
    expect(a.nonce.length, 24);
    expect(a.ct.length, 3 + 16);
    expect(a.nonce, isNot(b.nonce));
    expect(await SymmetricCipher.decrypt(k, a, aad: [9]), [1, 2, 3]);
  });

  test('wrong key, tampered ct, short ct and aad mismatch fail', () async {
    final e = await SymmetricCipher.encrypt(key, [1, 2, 3, 4], 'k', aad: [9]);
    final failing = <Future<Object?> Function()>[
      () => SymmetricCipher.decrypt(SymmetricCipher.newKey(), e, aad: [9]),
      () => SymmetricCipher.decrypt(
        key,
        relabel(e, ct: [...e.ct]..[0] ^= 1),
        aad: [9],
      ),
      () => SymmetricCipher.decrypt(
        key,
        relabel(e, ct: e.ct.sublist(0, 15)),
        aad: [9],
      ),
      () => SymmetricCipher.decrypt(key, e, aad: [8]),
      () => SymmetricCipher.decrypt(key, e),
    ];
    for (final f in failing) {
      await expectLater(f(), throwsA(isA<DecryptionFailed>()));
    }
  });

  test('relabelled keyId fails', () async {
    final e = await SymmetricCipher.encrypt(key, [1], 'master');
    await expectLater(
      SymmetricCipher.decrypt(key, relabel(e, keyId: 'recovery')),
      throwsA(isA<DecryptionFailed>()),
    );
  });

  test('an unsupported envelope throws UnsupportedEnvelope', () async {
    final e = Envelope(
      v: 2,
      alg: 'x',
      keyId: 'k',
      nonce: Uint8List(24),
      ct: Uint8List(32),
    );
    await expectLater(
      SymmetricCipher.decrypt(key, e),
      throwsA(isA<UnsupportedEnvelope>()),
    );
  });

  test('a key that is not 32 bytes is a programming error', () {
    expect(
      () => SymmetricCipher.encrypt(Uint8List(16), [1], 'k'),
      throwsArgumentError,
    );
  });
}
