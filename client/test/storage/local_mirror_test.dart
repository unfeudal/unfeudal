// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Version;
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  test('schema version 1: items, outbox, kv', () async {
    final dir = await Directory.systemTemp.createTemp('mirror');
    final path = '${dir.path}/mirror-$testUserId.sqlite';
    LocalMirror.open(path).close();
    final db = sqlite3.open(path);
    expect(db.select('PRAGMA user_version').single.values.single, 1);
    final cols = {
      for (final t in ['items', 'outbox', 'kv'])
        t: [for (final r in db.select('PRAGMA table_info($t)')) r['name']],
    };
    expect(cols, {
      'items': ['id', 'json'],
      'outbox': [
        'item_id',
        'json',
        'base_revision',
        'state',
        'attempts',
        'last_error',
      ],
      'kv': ['key', 'value'],
    });
    db.close();
  });

  test('a file from a newer client is refused, never touched', () async {
    final dir = await Directory.systemTemp.createTemp('mirror');
    final path = '${dir.path}/m.sqlite';
    sqlite3.open(path)
      ..execute('PRAGMA user_version = 2')
      ..close();
    expect(
      () => LocalMirror.open(path),
      throwsA(isA<MirrorTooNew>().having((e) => e.found, 'found', 2)),
    );
    final db = sqlite3.open(path);
    expect(
      db.select("SELECT name FROM sqlite_master WHERE type = 'table'"),
      isEmpty,
    );
    db.close();
  });

  test(
    'items: upsert, read, delete; an older revision is ignored unless accepted',
    () {
      final m = LocalMirror.inMemory();
      final a = newId();
      m.upsertItems([wireItem(a, revision: 3)]);
      m.upsertItems([wireItem(a, revision: 2)]);
      expect(m.item(a)!.revision, 3);
      m.upsertItems([wireItem(a, revision: 3, deleted: true)]);
      expect(m.item(a)!.deleted, isTrue);
      m.upsertItems([wireItem(a, revision: 1)], acceptOlder: true);
      expect(m.item(a)!.revision, 1);
      m.deleteItems([a]);
      expect(m.items(), isEmpty);
    },
  );

  test('outbox keeps the first base revision and queue position, failures lead to rejected', () {
    final m = LocalMirror.inMemory();
    final a = newId(), b = newId();
    m
      ..enqueue(wireItem(a, revision: 4), baseRevision: 4)
      ..enqueue(wireItem(b, revision: 0), baseRevision: 0)
      ..enqueue(wireItem(a, revision: 4, deleted: true), baseRevision: 9);
    expect(
      [for (final e in m.outbox()) (e.item.id, e.baseRevision, e.item.deleted)],
      [(a, 4, true), (b, 0, false)],
    );
    expect(m.recordOutboxFailure(a, 'invalid_request'), 1);
    expect(m.recordOutboxFailure(a, 'invalid_request'), 2);
    m.rejectOutbox(a);
    final e = m.outbox().first;
    expect(
      (e.state, e.attempts, e.lastError),
      (OutboxState.rejected, 2, 'invalid_request'),
    );
    m.retryOutbox(a);
    expect(
      (m.outbox().first.state, m.outbox().first.attempts),
      (OutboxState.pending, 0),
    );
    m.enqueue(wireItem(b, revision: 0), baseRevision: 0);
    m.rejectOutbox(b);
    m.enqueue(wireItem(b, revision: 0, deleted: true), baseRevision: 0);
    expect(
      m.outbox().last.state,
      OutboxState.pending,
    ); // a new edit makes a rejected entry pending again
    m.rebaseOutbox(a, 5);
    expect(m.outbox().first.baseRevision, 5);
    m.removeOutbox(a);
    expect(m.outbox().map((e) => e.item.id), [b]);
  });

  test('kv: every key, null removes', () {
    final m = LocalMirror.inMemory();
    for (final k in KvKey.values) {
      m.setKv(k, '${k.name}-v');
    }
    expect(
      [for (final k in KvKey.values) m.getKv(k)],
      [for (final k in KvKey.values) '${k.name}-v'],
    );
    m.setKv(KvKey.cursor, null);
    expect(m.getKv(KvKey.cursor), isNull);
  });

  test('accepted restore resets its keys', () {
    final restore = LocalMirror.inMemory()
      ..upsertItems([wireItem(newId())])
      ..enqueue(wireItem(newId(), revision: 0), baseRevision: 0);
    for (final k in KvKey.values) {
      restore.setKv(k, 'x');
    }
    restore.resetForRestore();
    expect(
      restore.items(),
      hasLength(1),
    ); // replaced by the full pull, not wiped up front
    expect(restore.outbox(), hasLength(1));
    expect(
      {for (final k in KvKey.values) k: restore.getKv(k)},
      {
        KvKey.cursor: null,
        KvKey.orgCursor: null,
        KvKey.orgBlock: null,
        KvKey.bundle: 'x',
        KvKey.apiInfo: 'x',
        KvKey.refusedEpoch: 'x',
        KvKey.ledger: 'x',
        KvKey.keyring: 'x',
        KvKey.anchors: null,
      },
    );
  });
}
