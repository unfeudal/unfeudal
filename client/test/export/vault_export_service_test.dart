// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/export/vault_export_service.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  test('personal readable items only: no org item, no trashed one, unreadable ones counted', () async {
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
      type: 'host',
      meta: hostJson('foreign'),
    );
    final org = Item.fromJson({
      ...(await sealItem(key, type: 'host', meta: hostJson('shared'))).toJson(),
      'scope': 'org',
      'orgId': newId(),
      'folderId': newId(),
    });
    m.upsertItems([foreign, org]);
    await v.reload();
    final out = await exportVault(
      v,
      passphrase: 'twelve chars!',
      kdf: KdfParams.testing,
      now: DateTime.utc(2026, 10, 15),
    );
    expect((out.count, out.unreadable), (2, 1));
    final back = await VaultExport.open(
      out.text,
      'twelve chars!',
      allowTestingKdf: true,
    );
    expect(back.items.map((i) => i['id']), unorderedEquals([host, ident]));
    final id = back.items.firstWhere((i) => i['id'] == ident);
    expect(
      (id['type'], id['folderId'], (id['secret']! as Map)['password']),
      ('identity', null, 'hunter2-hunter2'),
    );
    final plain =
        jsonDecode((await exportVault(v)).text) as Map<String, Object?>;
    expect(
      (plain['format'], plain.containsKey('warning')),
      ('unfeudal-export-plain', true),
    );
  });
}
