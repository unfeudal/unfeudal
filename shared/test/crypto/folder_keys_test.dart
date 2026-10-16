// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const fA = '7e9a1c3e-5f7b-4d9f-b1a3-c5e7a9b1d3f5';
const fB = '0a1b2c3d-4e5f-4a6b-9c7d-8e9f0a1b2c3d';
const user = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';

void main() {
  late SimpleKeyPair me;
  late List<int> myPub;
  setUpAll(() async {
    me = await X25519().newKeyPair();
    myPub = (await me.extractPublicKey()).bytes;
  });
  FolderKeys metaOnly(FolderKeys k) => FolderKeys(k.version, k.metaKey, null);

  test('generate gives two fresh 32-byte keys', () {
    final k = FolderKeys.generate(1);
    expect((k.version, k.metaKey.length, k.secretKey!.length), (1, 32, 32));
    expect(k.metaKey, isNot(k.secretKey));
    expect(() => FolderKeys.generate(0), throwsArgumentError);
  });

  test(
    'wrap and unwrap, with and without the secret key; wire form omits userId',
    () async {
      final k = FolderKeys.generate(2);
      final w = await WrappedFolderKeys.wrap(
        k,
        folderId: fA,
        recipientPublicKey: myPub,
        userId: user,
      );
      expect(
        (w.meta.keyId, w.secret!.keyId),
        ('sealed:folder:$fA:v2:meta', 'sealed:folder:$fA:v2:secret'),
      );
      final back = await WrappedFolderKeys.fromJson(
        jsonDecode(jsonEncode(w.toJson())),
      ).unwrap(fA, me);
      expect(back.version, 2);
      expect(back.metaKey, k.metaKey);
      expect(back.secretKey, k.secretKey);
      final wire = await WrappedFolderKeys.wrap(
        k,
        folderId: fA,
        recipientPublicKey: myPub,
        withSecret: false,
      );
      expect(wire.toJson().containsKey('userId'), isFalse);
      expect(wire.toJson()['secret'], isNull);
      expect((await wire.unwrap(fA, me)).secretKey, isNull);
    },
  );

  test('a wrapped key under another label throws KeyLabelMismatch', () async {
    final w = await WrappedFolderKeys.wrap(
      FolderKeys.generate(1),
      folderId: fA,
      recipientPublicKey: myPub,
    );
    await expectLater(w.unwrap(fB, me), throwsA(isA<KeyLabelMismatch>()));
    final bumped = WrappedFolderKeys.fromJson({...w.toJson(), 'version': 2});
    await expectLater(bumped.unwrap(fA, me), throwsA(isA<KeyLabelMismatch>()));
  });

  test(
    'history seals previous versions and checks keyIds and version on open',
    () async {
      final v1 = FolderKeys.generate(1),
          v2 = FolderKeys.generate(2),
          v3 = FolderKeys.generate(3);
      final h = await FolderKeyHistory.seal(v3, [v1, v2], folderId: fA);
      expect(
        (h.version, h.meta.keyId, h.secret!.keyId),
        (3, 'folder:$fA:v3:meta', 'folder:$fA:v3:secret'),
      );
      final opened = await FolderKeyHistory.fromJson(
        jsonDecode(jsonEncode(h.toJson())),
      ).open(v3, folderId: fA);
      expect(opened.map((k) => k.version), [1, 2]);
      expect(
        [
          opened[0].metaKey,
          opened[0].secretKey,
          opened[1].metaKey,
          opened[1].secretKey,
        ],
        [v1.metaKey, v1.secretKey, v2.metaKey, v2.secretKey],
      );
      final metaView = await h.open(metaOnly(v3), folderId: fA);
      expect(metaView.map((k) => k.secretKey), [null, null]);
      await expectLater(
        h.open(v3, folderId: fB),
        throwsA(isA<KeyLabelMismatch>()),
      );
      await expectLater(
        h.open(FolderKeys(4, v3.metaKey, v3.secretKey), folderId: fA),
        throwsA(isA<KeyLabelMismatch>()),
      );
      await expectLater(
        h.open(FolderKeys.generate(3), folderId: fA),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => FolderKeyHistory.seal(v2, [v3], folderId: fA),
        throwsArgumentError,
      );
    },
  );

  test(
    'continues accepts the same key or a history that leads to it',
    () async {
      final v1 = FolderKeys.generate(1), v3 = FolderKeys.generate(3);
      expect(continues(v1, v1, const []), isTrue);
      expect(continues(v1, v3, [v1, FolderKeys.generate(2)]), isTrue);
      expect(continues(metaOnly(v1), v3, [v1]), isTrue);
      expect(continues(metaOnly(v1), v3, [metaOnly(v1)]), isTrue);
    },
  );

  test('continues refuses a changed key, a changed secret or a rollback', () {
    final v1 = FolderKeys.generate(1), v3 = FolderKeys.generate(3);
    expect(
      continues(
        v1,
        FolderKeys(1, FolderKeys.generate(1).metaKey, v1.secretKey),
        const [],
      ),
      isFalse,
    );
    expect(
      continues(
        v1,
        FolderKeys(1, v1.metaKey, FolderKeys.generate(1).secretKey),
        const [],
      ),
      isFalse,
    );
    expect(continues(v1, v3, const []), isFalse);
    expect(
      continues(v1, v3, [
        FolderKeys(1, v1.metaKey, FolderKeys.generate(1).secretKey),
      ]),
      isFalse,
    );
    expect(continues(v1, v3, [metaOnly(v1)]), isFalse);
    expect(continues(v3, v1, [v1]), isFalse);
  });
}
