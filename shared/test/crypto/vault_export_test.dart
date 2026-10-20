// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final items = [
    {
      'id': '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20',
      'type': 'host',
      'folderId': null,
      'meta': {'schemaVersion': 1, 'name': 'web', 'address': '10.0.0.5'},
      'secret': null,
    },
    {
      'id': '2e4f6a8c-0b1d-4e3f-a5b7-c9d1e3f5a7b9',
      'type': 'identity',
      'folderId': null,
      'meta': {
        'schemaVersion': 1,
        'name': 'pw',
        'kind': 'password',
        'publicKey': null,
      },
      'secret': {
        'schemaVersion': 1,
        'kind': 'password',
        'privateKeyPem': null,
        'passphrase': null,
        'password': 'hunter2-hunter2',
      },
    },
  ];
  final at = DateTime.utc(2026, 10, 15, 9);
  const pass = 'twelve chars!';

  test('sealed export: its shape, nothing in clear', () async {
    final text = await VaultExport.seal(
      items,
      pass,
      kdf: KdfParams.testing,
      now: at,
    );
    final j = jsonDecode(text) as Map<String, Object?>;
    expect(j.keys, ['format', 'v', 'kdf', 'salt', 'data']);
    expect(
      (
        j['format'],
        j['v'],
        (j['data']! as Map)['keyId'],
        unb64(j['salt']! as String).length,
      ),
      ('unfeudal-export', 1, 'export', 16),
    );
    expect(text, isNot(contains('hunter2')));
  });

  test('key, keyId and aad of the sealed export', () async {
    final j = jsonDecode(
      await VaultExport.seal(items, pass, kdf: KdfParams.testing, now: at),
    ) as Map<String, Object?>;
    final key = await hkdf32(
      await argon2id(pass, unb64(j['salt']! as String), KdfParams.testing),
      'unfeudal/export/v1',
    );
    final plain = await SymmetricCipher.decrypt(
      key,
      Envelope.fromJson(j['data']),
      aad: utf8.encode('unfeudal-export/v1'),
    );
    expect(jsonDecode(utf8.decode(plain)), {
      'exportedAt': '2026-10-15T09:00:00.000Z',
      'items': items,
    });
  });

  test('passphrase under 12 code points is WeakPassword', () async {
    await expectLater(
      VaultExport.seal(items, 'café court', kdf: KdfParams.testing),
      throwsA(isA<WeakPassword>()),
    );
  });

  test('plaintext export: its own format, a warning, the same content', () {
    final j =
        jsonDecode(VaultExport.plain(items, now: at)) as Map<String, Object?>;
    expect(j.keys, ['format', 'v', 'warning', 'exportedAt', 'items']);
    expect(
      (j['format'], j['v'], j['exportedAt']),
      ('unfeudal-export-plain', 1, '2026-10-15T09:00:00.000Z'),
    );
    expect(j['items'], items);
  });
}
