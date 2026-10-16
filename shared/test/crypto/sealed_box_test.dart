// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  const purpose = 'folder:11111111-1111-4111-8111-111111111111:v1:meta';
  late SimpleKeyPair me, other;
  late List<int> myPub;
  setUpAll(() async {
    me = await X25519().newKeyPairFromSeed(List.filled(32, 1));
    other = await X25519().newKeyPair();
    myPub = (await me.extractPublicKey()).bytes;
  });

  Envelope withCt(Envelope e, List<int> ct) => Envelope(
    v: 1,
    alg: Envelope.xchacha,
    keyId: e.keyId,
    nonce: e.nonce,
    ct: Uint8List.fromList(ct),
  );

  test('opens the known answer', () async {
    expect(b64(myPub), 'pOCSkrZRwni5dyxWn1-puxPZBrRqtoyd-dwrRAn4ogk');
    final e = Envelope.fromJson({
      'v': 1,
      'alg': 'xchacha20poly1305',
      'keyId': 'sealed:$purpose',
      'nonce': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'ct': 'zo060cy2M-x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVkOv1u5UKncrvhWMCqnoZVthdKkBAb0HGtmfZ1K5YHvGVJ-iLXmk7mAmgWHCxszBdg',
    });
    expect(await SealedBox.open(e, me, purpose), List.filled(32, 7));
  });

  test('round-trips; ct carries the ephemeral key first', () async {
    final e = await SealedBox.seal([1, 2, 3], myPub, purpose);
    expect((e.keyId, e.ct.length), ('sealed:$purpose', 32 + 3 + 16));
    expect(await SealedBox.open(e, me, purpose), [1, 2, 3]);
  });

  test('wrong purpose throws KeyLabelMismatch; wrong recipient or tampering DecryptionFailed', () async {
    final e = await SealedBox.seal([1], myPub, purpose);
    await expectLater(
      SealedBox.open(
        e,
        me,
        'folder:11111111-1111-4111-8111-111111111111:v2:meta',
      ),
      throwsA(isA<KeyLabelMismatch>()),
    );
    await expectLater(
      SealedBox.open(e, other, purpose),
      throwsA(isA<DecryptionFailed>()),
    );
    await expectLater(
      SealedBox.open(withCt(e, [...e.ct]..[40] ^= 1), me, purpose),
      throwsA(isA<DecryptionFailed>()),
    );
    await expectLater(
      SealedBox.open(withCt(e, e.ct.sublist(0, 47)), me, purpose),
      throwsA(isA<DecryptionFailed>()),
    );
  });

  test('an all-zero shared secret is refused', () async {
    final e = await SealedBox.seal([1], myPub, purpose);
    await expectLater(
      SealedBox.open(
        withCt(e, [...List.filled(32, 0), ...e.ct.sublist(32)]),
        me,
        purpose,
      ),
      throwsA(isA<DecryptionFailed>()),
    );
    await expectLater(
      SealedBox.seal([1], List.filled(32, 0), purpose),
      throwsA(isA<DecryptionFailed>()),
    );
  });
}
