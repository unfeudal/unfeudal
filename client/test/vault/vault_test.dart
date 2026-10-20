// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  final key = SymmetricCipher.newKey();

  test('entries: ok, unreadable, unsupported, read-only; org items and tombstones are not listed', () async {
    final m = LocalMirror.inMemory();
    final ok = await sealItem(key, meta: hostJson('web'));
    final unreadable = await sealItem(
      SymmetricCipher.newKey(),
      meta: hostJson('x'),
    );
    final unsupported = Item.fromJson(
      wireItem(newId()).toJson()..['type'] = 'futureThing',
    );
    final newer = await sealItem(
      key,
      meta: {...hostJson('n'), 'schemaVersion': 2},
    );
    final org = Item.fromJson(
      wireItem(newId()).toJson()
        ..['scope'] = 'org'
        ..['orgId'] = newId()
        ..['folderId'] = newId(),
    );
    m.upsertItems([
      ok,
      unreadable,
      unsupported,
      newer,
      org,
      wireItem(newId(), purged: true),
    ]);
    final v = await testVault(key, m);
    expect(
      {for (final e in v.entries) e.id: e.state},
      {
        ok.id: EntryState.ok,
        unreadable.id: EntryState.unreadable,
        unsupported.id: EntryState.unsupported,
        newer.id: EntryState.readOnly,
      },
    );
    expect(v.entry(ok.id)!.name, 'web');
    expect(
      v.ofKind(ItemKind.host).map((e) => e.id),
      containsAll([ok.id, unreadable.id, newer.id]),
    );
  });

  test('a replayed _seq is ignored and the previous entry kept', () async {
    final m = LocalMirror.inMemory();
    final id = newId();
    m.upsertItems([
      await sealItem(key, id: id, meta: hostJson('v5'), seq: 5, revision: 5),
    ]);
    final v = await testVault(key, m);
    // An earlier payload under a new revision.
    m.upsertItems([
      await sealItem(key, id: id, meta: hostJson('v2'), seq: 2, revision: 6),
    ]);
    var replays = 0;
    v.onReplay = (_) => replays++;
    await v.reload();
    expect((v.entry(id)!.name, v.entry(id)!.item.revision), ('v5', 6));
    expect(replays, 1);
    // After a restart the entry shows as unreadable, never dropped.
    final fresh = await testVault(key, m);
    expect(fresh.entry(id)!.state, EntryState.unreadable);
  });

  test('marks rise only from server rows, not from the outbox', () async {
    final m = LocalMirror.inMemory();
    final id = newId();
    final v = await testVault(key, m);
    m.enqueue(
      await sealItem(key, id: id, meta: hostJson('mine'), seq: 9, revision: 0),
      baseRevision: 0,
    );
    await v.reload();
    expect(v.ledger.mark(id, PayloadPart.meta), 0);
    confirmOutbox(m);
    await v.reload();
    expect(v.ledger.mark(id, PayloadPart.meta), 9);
  });

  test('a reload with nothing changed keeps the sealed ledger; after a restore every row is checked again', () async {
    final m = LocalMirror.inMemory();
    final id = newId();
    m.upsertItems([await sealItem(key, id: id, meta: hostJson('web'), seq: 3)]);
    final v = await testVault(key, m);
    final sealed = m.getKv(KvKey.ledger);
    await v.reload();
    expect(m.getKv(KvKey.ledger), sealed);
    await v.ledger.reset();
    await v.reload();
    expect(v.ledger.mark(id, PayloadPart.meta), 3);
  });

  test('a write shows at once from its plaintext; a second edit at the same revision too', () async {
    final m = LocalMirror.inMemory();
    final v = await testVault(key, m);
    final id = await v.upsertItem(type: 'host', meta: hostJson('a'));
    expect((v.entry(id)!.name, v.entry(id)!.pending), ('a', true));
    await v.upsertItem(type: 'host', id: id, meta: hostJson('b'));
    expect(v.entry(id)!.name, 'b');
    await v.reload();
    expect(v.entry(id)!.name, 'b');
  });

  test('no plaintext reaches the mirror file', () async {
    final dir = await Directory.systemTemp.createTemp('vault');
    final path = '${dir.path}/mirror.sqlite';
    final m = LocalMirror.open(path);
    final v = await testVault(key, m);
    await v.upsertItem(
      type: 'host',
      meta: hostJson('prod-db', address: 'db.internal.example'),
    );
    confirmOutbox(m);
    await v.reload();
    m.close();
    final bytes = String.fromCharCodes(File(path).readAsBytesSync());
    expect(bytes.contains('prod-db'), isFalse);
    expect(bytes.contains('db.internal.example'), isFalse);
  });

  test('lock destroys the key and the entries', () async {
    final m = LocalMirror.inMemory()
      ..upsertItems([await sealItem(key, meta: hostJson('web'))]);
    final v = await testVault(key, m);
    v.lock();
    expect(v.isUnlocked, false);
    expect(v.entries, isEmpty);
    await expectLater(
      v.upsertItem(type: 'host', meta: hostJson('x')),
      throwsStateError,
    );
  });
}
