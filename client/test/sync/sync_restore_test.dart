// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/sync_engine.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/sync_harness.dart';

const newEpoch = 'AAAAAAAAAAAAAAAAAAAAAA';
String? storedEpoch(LocalMirror m) =>
    ApiInfo.fromJson(jsonDecode(m.kv(KvKey.apiInfo)!)).instanceEpoch;
int syncCalls(SyncHarness h) =>
    h.requests.where((r) => r == 'GET /api/v1/sync').length;

void main() {
  test('changed epoch pauses sync; local writes still queue', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    await e.syncNow();
    h.restore(h.snapshot(), epoch: newEpoch);
    final before = syncCalls(h);
    await e.syncNow();
    expect(
      (e.isRestorePending, e.isRestoreRefused, syncCalls(h)),
      (true, false, before),
    );
    expect(storedEpoch(m), 'q83vEjRWeJCrze8SNFZ4kA');
    await e.write(wireItem(newId(), revision: 0));
    expect(h.requests.where((r) => r.startsWith('PUT ')), isEmpty);
  });

  test('missing epoch pauses and never replaces the stored one', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    await e.syncNow();
    h.instanceEpoch = null;
    await e.syncNow();
    expect(e.isRestorePending, isTrue);
    expect(storedEpoch(m), 'q83vEjRWeJCrze8SNFZ4kA');
  });

  test('cursor_ahead pauses sync', () async {
    final h = SyncHarness();
    final (e, _, _) = await h.engine();
    final empty = h.snapshot();
    h.serverPut(wireItem(newId(), revision: 0));
    await e.syncNow();
    h.restore(empty, epoch: h.instanceEpoch); // same epoch, older data
    await e.syncNow();
    expect(e.isRestorePending, isTrue);
  });

  test('refuse: read-only toward this server, kept after a restart, Accept still available', () async {
    final h = SyncHarness();
    final (e, m, login) = await h.engine();
    await e.syncNow();
    h.restore(h.snapshot(), epoch: newEpoch);
    await e.syncNow();
    await e.refuseRestore();
    expect(
      (m.kv(KvKey.refusedEpoch), e.isReadOnly, e.isRestoreRefused),
      (newEpoch, true, true),
    );
    await expectLater(
      e.write(wireItem(newId(), revision: 0)),
      throwsA(isA<ReadOnlyException>()),
    );
    final api = ApiClient(h.baseUrl, h.client)..accessToken = login.accessToken;
    final restarted = SyncEngine(api: api, mirror: m, deviceId: login.deviceId);
    expect((restarted.isRestorePending, restarted.isReadOnly), (true, true));
  });

  test('accept: marks and anchors emptied, pins and keyring kept, server items taken as they are, outbox pushed again, epoch stored', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    var ledgerReset = 0;
    e.onRestoreAccepted = () async => ledgerReset++;
    final kept = newId(), lost = newId();
    h.serverPut(wireItem(kept, revision: 0));
    await e.syncNow();
    final backup = h.snapshot(); // kept at revision 1
    h.serverPut(wireItem(kept));
    h.serverPut(wireItem(lost, revision: 0));
    await e.syncNow();
    expect(m.item(kept)!.revision, 2);
    expect(m.item(lost), isNotNull);
    m
      ..setKv(KvKey.ledger, 'sealed')
      ..setKv(KvKey.keyring, 'sealed')
      ..setKv(KvKey.anchors, 'x');
    h.restore(backup, epoch: newEpoch);
    await e.syncNow();
    await e.refuseRestore();
    final queued = newId();
    m.enqueue(wireItem(queued, revision: 0), baseRevision: 0);
    await e.acceptRestore();
    expect(ledgerReset, 1);
    expect(
      (m.kv(KvKey.ledger), m.kv(KvKey.keyring), m.kv(KvKey.anchors)),
      ('sealed', 'sealed', null),
    );
    expect(m.item(kept)!.revision, 1);
    expect(m.item(lost), isNull); // older revision taken; vanished item removed
    expect(h.serverItem(queued), isNotNull);
    expect(
      (
        storedEpoch(m),
        m.kv(KvKey.refusedEpoch),
        e.isRestorePending,
        e.isReadOnly,
      ),
      (newEpoch, null, false, false),
    );
  });

  test('accept: the API keeps refusing writes until the accepted round has negotiated', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    await e.syncNow();
    h.restore(h.snapshot(), epoch: newEpoch);
    await e.syncNow();
    await e.refuseRestore();
    final info = Completer<void>();
    h.holdInfo = info.future;
    final accepted = e.acceptRestore();
    await pumpEventQueue();
    expect((e.isReadOnly, e.api.isReadOnly()), (false, true));
    info.complete();
    await accepted;
    expect((e.isReadOnly, e.api.isReadOnly()), (false, false));
  });

  test('outside an accepted restore an older revision is ignored', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    final id = newId();
    final v1 = h.serverPut(wireItem(id, revision: 0));
    h.serverPut(wireItem(id));
    await e.syncNow();
    h.serveOlder(v1);
    await e.syncNow();
    expect(m.item(id)!.revision, 2);
  });
}
