// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const id = '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20';
const org = '3c5e7a9b-1d2f-4e6a-8b0c-2d4f6a8c0e1a';
const f1 = '7e9a1c3e-5f7b-4d9f-b1a3-c5e7a9b1d3f5';
const f2 = '0a1b2c3d-4e5f-4a6b-9c7d-8e9f0a1b2c3d';

PayloadAad personal({
  String type = 'host',
  PayloadPart part = PayloadPart.meta,
  String? folderId,
}) => PayloadAad(
  itemId: id,
  part: part,
  type: type,
  scope: ItemScope.personal,
  orgId: null,
  folderId: folderId,
);
PayloadAad orgAad({
  String type = 'host',
  String? folderId = f1,
  String itemId = id,
}) => PayloadAad(
  itemId: itemId,
  part: PayloadPart.meta,
  type: type,
  scope: ItemScope.org,
  orgId: org,
  folderId: folderId,
);

void main() {
  final key = SymmetricCipher.newKey();

  test('AAD text is the six fields joined by /', () {
    expect(utf8.decode(personal().bytes), '$id/meta/host/personal//');
    expect(utf8.decode(orgAad().bytes), '$id/meta/host/org/$org/$f1');
  });

  test('_seq is added last and stripped on open', () async {
    final e = await PayloadCrypto.seal(
      personal(),
      {'name': 'web'},
      key,
      KeyIds.user,
      seq: 7,
    );
    final raw = utf8.decode(
      await SymmetricCipher.decrypt(key, e, aad: personal().bytes),
    );
    expect(raw, '{"name":"web","_seq":7}');
    final opened = await PayloadCrypto.open(personal(), e, key);
    expect(opened.json, {'name': 'web'});
    expect(opened.seq, 7);
  });

  test(
    'a moved, retyped, rescoped or swapped-part payload fails to open',
    () async {
      final e = await PayloadCrypto.seal(
        personal(),
        {'a': 1},
        key,
        KeyIds.user,
        seq: 1,
      );
      for (final aad in [
        personal(folderId: f1),
        personal(type: 'snippet'),
        personal(part: PayloadPart.secret),
        const PayloadAad(
          itemId: f2,
          part: PayloadPart.meta,
          type: 'host',
          scope: ItemScope.personal,
          orgId: null,
          folderId: null,
        ),
      ]) {
        await expectLater(
          PayloadCrypto.open(aad, e, key),
          throwsA(isA<DecryptionFailed>()),
        );
      }
      // Same keyId, other org: only the AEAD binding can refuse it.
      final o = await PayloadCrypto.seal(
        orgAad(),
        {'a': 1},
        key,
        KeyIds.folder(f1, 1, PayloadPart.meta),
        seq: 1,
      );
      final otherOrg = const PayloadAad(
        itemId: id,
        part: PayloadPart.meta,
        type: 'host',
        scope: ItemScope.org,
        orgId: '9b8a7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d',
        folderId: f1,
      );
      await expectLater(
        PayloadCrypto.open(otherOrg, o, key),
        throwsA(isA<DecryptionFailed>()),
      );
    },
  );

  test('org payload under another folder\'s keyId is refused', () async {
    final good = await PayloadCrypto.seal(
      orgAad(),
      {'a': 1},
      key,
      KeyIds.folder(f1, 1, PayloadPart.meta),
      seq: 1,
    );
    expect((await PayloadCrypto.open(orgAad(), good, key)).json, {'a': 1});
    final folderItem = orgAad(type: 'folder', itemId: f2, folderId: f1);
    final ownKey = await PayloadCrypto.seal(
      folderItem,
      {'a': 1},
      key,
      KeyIds.folder(f2, 2, PayloadPart.meta),
      seq: 1,
    );
    expect((await PayloadCrypto.open(folderItem, ownKey, key)).seq, 1);
    final wrongFolder = await SymmetricCipher.encrypt(
      key,
      utf8.encode('{"a":1}'),
      KeyIds.folder(f2, 1, PayloadPart.meta),
      aad: orgAad().bytes,
    );
    await expectLater(
      PayloadCrypto.open(orgAad(), wrongFolder, key),
      throwsA(isA<DecryptionFailed>()),
    );
    final wrongPart = await SymmetricCipher.encrypt(
      key,
      utf8.encode('{}'),
      KeyIds.folder(f1, 1, PayloadPart.secret),
      aad: orgAad().bytes,
    );
    await expectLater(
      PayloadCrypto.open(orgAad(), wrongPart, key),
      throwsA(isA<DecryptionFailed>()),
    );
    expect(
      () => PayloadCrypto.seal(
        orgAad(),
        {},
        key,
        KeyIds.folder(f2, 1, PayloadPart.meta),
        seq: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => PayloadCrypto.seal(personal(), {}, key, 'master', seq: 1),
      throwsArgumentError,
    );
  });

  test('invalid _seq is a FormatException; absent means no mark', () async {
    Future<OpenedPayload> openText(String text) async => PayloadCrypto.open(
      personal(),
      await SymmetricCipher.encrypt(
        key,
        utf8.encode(text),
        'user',
        aad: personal().bytes,
      ),
      key,
    );
    expect((await openText('{"a":1}')).seq, isNull);
    for (final text in [
      '{"_seq":0}',
      '{"_seq":"1"}',
      '{"_seq":null}',
      '{"_seq":1.5}',
      '[1]',
      '"x"',
      'not json',
    ]) {
      await expectLater(openText(text), throwsFormatException, reason: text);
    }
  });

  test('seal refuses seq < 1 and a caller-supplied _seq', () {
    expect(
      () => PayloadCrypto.seal(personal(), {}, key, 'user', seq: 0),
      throwsArgumentError,
    );
    expect(
      () => PayloadCrypto.seal(personal(), {'_seq': 3}, key, 'user', seq: 1),
      throwsArgumentError,
    );
  });

  test('PayloadAad.of reads the item fields', () {
    final item = Item.fromJson({
      'id': id,
      'type': 'snippet',
      'scope': 'org',
      'orgId': org,
      'folderId': f1,
      'schemaVersion': 1,
      'deleted': false,
      'meta': {
        'v': 1,
        'alg': 'xchacha20poly1305',
        'keyId': 'user',
        'nonce': b64(List.filled(24, 0)),
        'ct': b64(List.filled(16, 0)),
      },
      'secret': null,
    });
    expect(
      utf8.decode(PayloadAad.of(item, PayloadPart.secret).bytes),
      '$id/secret/snippet/org/$org/$f1',
    );
  });
}
