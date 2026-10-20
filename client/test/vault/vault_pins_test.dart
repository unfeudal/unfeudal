// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  final key = SymmetricCipher.newKey();
  final host = newId();
  Map<String, Object?> pin(String c) => {
    'schemaVersion': 1,
    'hostItemId': host,
    'keyType': 'ssh-ed25519',
    'sha256Fingerprint': 'SHA256:${c * 43}',
  };

  test('first sight of a synced pin seeds the ledger', () async {
    final m = LocalMirror.inMemory()
      ..upsertItems([await sealItem(key, type: 'knownHost', meta: pin('A'))]);
    final v = await testVault(key, m);
    expect(v.ledger.hostPin(host)!.sha256Fingerprint, 'SHA256:${'A' * 43}');
  });

  test('ledger pin wins over a reverted or deleted knownHost item', () async {
    final m = LocalMirror.inMemory();
    final kh = await sealItem(
      key,
      type: 'knownHost',
      meta: pin('A'),
      revision: 1,
    );
    m.upsertItems([kh]);
    final v = await testVault(key, m);
    // The server swaps the key.
    m.upsertItems([
      await sealItem(
        key,
        id: kh.id,
        type: 'knownHost',
        meta: pin('B'),
        seq: 2,
        revision: 2,
      ),
    ]);
    await v.reload();
    expect(v.trustedPin(host)!.sha256Fingerprint, 'SHA256:${'A' * 43}');
    m.upsertItems([
      wireItem(kh.id, type: 'knownHost', purged: true, revision: 3),
    ]);
    await v.reload();
    expect(v.trustedPin(host)!.sha256Fingerprint, 'SHA256:${'A' * 43}');
    final restarted = await testVault(key, m); // the ledger is on disk, sealed
    expect(restarted.trustedPin(host)!.sha256Fingerprint, 'SHA256:${'A' * 43}');
  });

  test(
    'pinHostKey updates the ledger and the winning knownHost item',
    () async {
      final m = LocalMirror.inMemory();
      final low = '00000000-0000-4000-8000-0000000000aa';
      m.upsertItems([
        await sealItem(key, id: low, type: 'knownHost', meta: pin('A')),
        await sealItem(key, type: 'knownHost', meta: pin('C')),
      ]);
      final v = await testVault(key, m);
      await v.pinHostKey(host, 'ssh-ed25519', 'SHA256:${'B' * 43}');
      expect(v.trustedPin(host)!.sha256Fingerprint, 'SHA256:${'B' * 43}');
      expect(m.outbox().single.item.id, low);
    },
  );
}
