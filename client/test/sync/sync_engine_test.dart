// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/sync_harness.dart';

void main() {
  test('write queues, push creates with If-Match 0, the stored item replaces the outbox', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    final id = newId();
    await e.write(wireItem(id, revision: 0));
    await e.syncNow();
    expect(h.serverItem(id)!.revision, 1);
    expect(m.item(id)!.revision, 1);
    expect(m.outbox(), isEmpty);
  });

  test('pull pages until done and stores the cursor', () async {
    final h = SyncHarness(pageSize: 2);
    final (e, m, _) = await h.engine();
    for (var i = 0; i < 5; i++) {
      h.serverPut(wireItem(newId(), revision: 0));
    }
    await e.syncNow();
    expect(m.items(), hasLength(5));
    expect(m.getKv(KvKey.cursor), '${h.itemsSeq}');
    expect(h.requests.where((r) => r == 'GET /api/v1/sync'), hasLength(3));
  });

  test('the vault reloads after a round that changed the mirror, not after an idle one', () async {
    final h = SyncHarness();
    final (e, _, _) = await h.engine();
    var reloads = 0;
    e.onChanged = () async => reloads++;
    h.serverPut(wireItem(newId(), revision: 0));
    await e.syncNow();
    await e.syncNow();
    expect(reloads, 1);
  });

  test('an edit made during the push is rebased and pushed next, without a conflict', () async {
    final h = SyncHarness();
    final copies = <Item>[];
    final (e, m, _) = await h.engine(copies: copies);
    final id = newId();
    h.onPut = (_) {
      h.onPut = null;
      // The user edits while the PUT is in flight.
      m.enqueue(wireItem(id, revision: 0, deleted: true), baseRevision: 0);
    };
    await e.write(wireItem(id, revision: 0));
    await e.syncNow();
    expect((h.serverItem(id)!.revision, h.serverItem(id)!.deleted), (2, true));
    expect(m.outbox(), isEmpty);
    expect(copies, isEmpty);
  });

  test('409 keeps the server version and queues a conflict copy', () async {
    final h = SyncHarness();
    final copies = <Item>[];
    final (e, m, _) = await h.engine(copies: copies);
    final id = newId();
    h.serverPut(wireItem(id, revision: 0)); // revision 1 elsewhere
    await e.write(wireItem(id, revision: 0)); // our create races it
    await e.syncNow();
    expect(m.item(id)!.updatedDevice, isNot(e.deviceId));
    expect(copies, hasLength(1));
    // Pushed by the follow-up round of this syncNow.
    expect(h.serverItem(copies.single.id), isNotNull);
    expect(m.outbox(), isEmpty);
  });

  test(
    'our own write whose response was lost is settled, not copied',
    () async {
      final h = SyncHarness();
      final copies = <Item>[];
      final (e, m, login) = await h.engine(copies: copies);
      final id = newId();
      final mine = wireItem(id, revision: 0);
      h.offline = true;
      await e.write(mine);
      // Stored as this device; the answer never arrived.
      h
        ..offline = false
        ..serverPut(mine, deviceId: login.deviceId);
      await e.syncNow();
      expect(copies, isEmpty);
      expect(m.outbox(), isEmpty);
    },
  );

  test('deletion wins: an edit of an item deleted or purged elsewhere becomes a copy', () async {
    for (final purge in [false, true]) {
      final h = SyncHarness();
      final copies = <Item>[];
      final (e, m, _) = await h.engine(copies: copies);
      final id = newId();
      h.serverPut(wireItem(id, revision: 0));
      await e.syncNow();
      purge ? h.purge(id) : h.serverPut(wireItem(id, deleted: true));
      await e.write(wireItem(id, revision: 1));
      await e.syncNow();
      expect(m.item(id)!.deleted, isTrue, reason: 'purge: $purge');
      expect(copies, hasLength(1), reason: 'purge: $purge');
    }
  });

  test(
    'profile conflict: our prefs go on top of the server revision',
    () async {
      final h = SyncHarness();
      final copies = <Item>[];
      final (e, m, _) = await h.engine(copies: copies);
      final id = newId();
      h.serverPut(wireItem(id, revision: 0, type: 'profile'));
      await e.write(wireItem(id, revision: 0, type: 'profile'));
      await e.syncNow();
      await e.syncNow();
      expect(copies, isEmpty);
      expect(h.serverItem(id)!.revision, 2);
    },
  );

  test(
    'knownHost conflict: the server copy is kept, no copy, nothing sent again',
    () async {
      final h = SyncHarness();
      final copies = <Item>[];
      final (e, m, _) = await h.engine(copies: copies);
      final id = newId();
      h.serverPut(wireItem(id, revision: 0, type: 'knownHost'));
      await e.write(wireItem(id, revision: 0, type: 'knownHost'));
      await e.syncNow();
      await e.syncNow();
      expect(copies, isEmpty);
      expect(m.outbox(), isEmpty);
      expect((h.serverItem(id)!.revision, m.item(id)!.revision), (1, 1));
    },
  );

  test('org block is stored raw with its cursor', () async {
    final h = SyncHarness()
      ..orgBlock = OrgBlock.fromJson({
        'orgCursor': 4,
        'orgs': [],
        'members': [],
        'teams': [],
        'acl': [],
        'folderTree': [],
        'wrappedKeys': [],
        'keyHistory': [],
        'keyRequests': [],
        'pendingRotations': [],
        'itemIds': [],
      });
    final (e, m, _) = await h.engine();
    await e.syncNow();
    expect(m.getKv(KvKey.orgCursor), '4');
    expect(m.getKv(KvKey.orgBlock), contains('"orgCursor":4'));
  });

  test('malformed page keeps local data and the loop alive', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    h.serverPut(wireItem(newId(), revision: 0));
    await e.syncNow();
    h.syncBodyOverride =
        '{"items": [{"id": "nope"}], "cursor": 9, "more": false}';
    await e.syncNow();
    expect(m.items(), hasLength(1));
    expect(e.lastError, isA<FormatException>());
    h.syncBodyOverride = null;
    await e.syncNow();
    expect(e.lastError, isNull);
  });

  test('malformed org block deletes nothing', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    h.serverPut(wireItem(newId(), revision: 0));
    await e.syncNow();
    h.syncBodyOverride =
        '{"items": [], "cursor": ${h.itemsSeq}, "more": false, "org": {"orgCursor": 1, "orgs": []}}';
    await e.syncNow();
    expect(m.items(), hasLength(1));
    expect(m.getKv(KvKey.orgBlock), isNull);
    expect(e.lastError, isA<FormatException>());
  });

  test('offline: outbox kept, online false; back online it pushes', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    h.offline = true;
    await e.write(wireItem(newId(), revision: 0));
    await e.syncNow();
    expect(e.online, false);
    expect(m.outbox(), hasLength(1));
    h.offline = false;
    await e.syncNow();
    expect(e.online, true);
    expect(m.outbox(), isEmpty);
  });

  test('timer runs a round every 30 s; syncNow calls coalesce', () async {
    final h = SyncHarness();
    final (e, _, _) = await h.engine();
    fakeAsync((async) {
      e.start();
      unawaited(e.syncNow());
      unawaited(e.syncNow());
      async.flushMicrotasks();
      int rounds() => h.requests.where((r) => r == 'GET /api/info').length;
      expect(rounds(), 2); // the start round plus one coalesced follow-up
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(rounds(), 3);
      e.stop();
    });
  });
}
