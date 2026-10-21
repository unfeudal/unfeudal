// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/export/vault_export_service.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  // A personal host and identity, a trashed host, an unreadable item and an org item.
  Future<({Vault vault, String host, String ident})> seededVault() async {
    final key = SymmetricCipher.newKey();
    final m = LocalMirror.inMemory();
    final v = await testVault(key, m);
    final host = await v.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    final ident = await v.upsertItem(
      type: 'identity',
      meta: {
        'schemaVersion': 1,
        'name': 'pw',
        'kind': 'password',
        'publicKey': null,
      },
      secret: {
        'schemaVersion': 1,
        'kind': 'password',
        'privateKeyPem': null,
        'passphrase': null,
        'password': 'hunter2-hunter2',
      },
    );
    await v.trashItem(await v.upsertItem(type: 'host', meta: hostJson('old')));
    final foreign = await sealItem(
      SymmetricCipher.newKey(),
      meta: hostJson('foreign'),
    );
    final org = Item.fromJson({
      ...(await sealItem(key, meta: hostJson('shared'))).toJson(),
      'scope': 'org',
      'orgId': newId(),
      'folderId': newId(),
    });
    m.upsertItems([foreign, org]);
    await v.reload();
    return (vault: v, host: host, ident: ident);
  }

  Map<String, Object?> decode(String text) =>
      jsonDecode(text) as Map<String, Object?>;
  List<Map<String, Object?>> itemsOf(Map<String, Object?> export) =>
      (export['items']! as List).cast<Map<String, Object?>>();

  test('personal readable items only: no org item, no trashed one, unreadable ones counted', () async {
    final seeded = await seededVault();
    final out = await exportVault(seeded.vault);
    expect((out.count, out.unreadable), (2, 1));
    expect(
      itemsOf(decode(out.text)).map((i) => i['id']),
      unorderedEquals([seeded.host, seeded.ident]),
    );
  });

  test('a passphrase seals the export; without one it is plain, with a warning and the decrypted items', () async {
    final seeded = await seededVault();
    final sealed = await exportVault(
      seeded.vault,
      passphrase: 'twelve chars!',
      kdf: KdfParams.testing,
      now: DateTime.utc(2026, 10, 15),
    );
    final plain = decode((await exportVault(seeded.vault)).text);
    expect(
      (
        decode(sealed.text)['format'],
        plain['format'],
        plain.containsKey('warning'),
      ),
      ('unfeudal-export', 'unfeudal-export-plain', true),
    );
    final id = itemsOf(plain).firstWhere((i) => i['id'] == seeded.ident);
    expect(
      (id['type'], id['folderId'], (id['secret']! as Map)['password']),
      ('identity', null, 'hunter2-hunter2'),
    );
  });
}
