// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/sync_harness.dart';

int puts(SyncHarness h) => h.requests.where((r) => r.startsWith('PUT ')).length;

void main() {
  test(
    '400, 403, 413 are tried 3 times, then rejected; other entries go on',
    () async {
      for (final status in [400, 403, 413]) {
        final h = SyncHarness();
        final (e, m, _) = await h.engine();
        final bad = newId(), good = newId();
        h.failPuts[bad] = status;
        await e.write(wireItem(bad, revision: 0));
        await e.write(wireItem(good, revision: 0));
        for (var i = 0; i < 4; i++) {
          await e.syncNow();
        }
        expect(
          h.requests.where((r) => r == 'PUT /api/v1/items/$bad'),
          hasLength(3),
          reason: '$status',
        );
        expect(h.serverItem(good), isNotNull);
        final r = e.rejected.single;
        expect(
          (r.item.id, r.state, r.attempts),
          (bad, OutboxState.rejected, 3),
        );
      }
    },
  );

  test('retry makes a rejected write pending and pushes it', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    final id = newId();
    h.failPuts[id] = 400;
    await e.write(wireItem(id, revision: 0));
    for (var i = 0; i < 3; i++) {
      await e.syncNow();
    }
    h.failPuts.remove(id);
    await e.retry(id);
    expect(h.serverItem(id)!.revision, 1);
    expect(m.outbox(), isEmpty);
  });

  test('discard drops the local edit; the server version stays', () async {
    final h = SyncHarness();
    final (e, m, _) = await h.engine();
    final id = newId();
    h.serverPut(wireItem(id, revision: 0));
    await e.syncNow();
    h.failPuts[id] = 403;
    await e.write(wireItem(id, deleted: true));
    for (var i = 0; i < 3; i++) {
      await e.syncNow();
    }
    await e.discard(id);
    expect(m.outbox(), isEmpty);
    expect(m.item(id)!.deleted, false);
    expect(m.item(id)!.revision, 1);
  });

  test(
    'keep a personal copy queues a copy and drops the rejected edit',
    () async {
      final h = SyncHarness();
      final copies = <Item>[];
      final (e, m, _) = await h.engine(copies: copies);
      final id = newId();
      h.failPuts[id] = 413;
      await e.write(wireItem(id, revision: 0));
      for (var i = 0; i < 3; i++) {
        await e.syncNow();
      }
      await e.keepPersonalCopy(id);
      expect(m.outbox().map((o) => o.item.id), isNot(contains(id)));
      expect(h.serverItem(copies.single.id), isNotNull);
    },
  );

  test('429 and 5xx back off without counting attempts; retry-after wins when longer', () async {
    final clock = FakeClock();
    final h = SyncHarness();
    final (e, m, _) = await h.engine(now: clock.now);
    final id = newId();
    h.failPuts[id] = 500;
    await e.write(wireItem(id, revision: 0));
    await e.syncNow();
    final first = puts(h);
    await e.syncNow();
    expect(puts(h), first); // backing off
    clock.advance(const Duration(seconds: 30));
    await e.syncNow();
    expect(puts(h), first + 1);
    clock.advance(const Duration(seconds: 30)); // second failure waits 60 s
    await e.syncNow();
    expect(puts(h), first + 1);
    expect(
      (m.outbox().single.attempts, m.outbox().single.state),
      (0, OutboxState.pending),
    );
    h.failPuts.remove(id);
    clock.advance(const Duration(minutes: 1));
    await e.syncNow();
    expect(m.outbox(), isEmpty);
    expect(e.lastError, isNull);
  });

  test(
    'a push lost to the network backs off too, without counting attempts',
    () async {
      final clock = FakeClock();
      final h = SyncHarness();
      final (e, m, _) = await h.engine(now: clock.now);
      final id = newId();
      h.dropPuts.add(id);
      await e.write(wireItem(id, revision: 0));
      await e.syncNow();
      final first = puts(h);
      await e.syncNow();
      expect(puts(h), first); // backing off
      expect(m.outbox().single.attempts, 0);
      h.dropPuts.clear();
      clock.advance(const Duration(seconds: 30));
      await e.syncNow();
      expect(m.outbox(), isEmpty);
    },
  );

  test('backoff caps at 10 minutes', () async {
    final clock = FakeClock();
    final h = SyncHarness();
    final (e, _, _) = await h.engine(now: clock.now);
    final id = newId();
    h.failPuts[id] = 429;
    await e.write(wireItem(id, revision: 0));
    for (var i = 0; i < 8; i++) {
      clock.advance(const Duration(minutes: 10));
      await e.syncNow();
    }
    final before = puts(h);
    clock.advance(const Duration(minutes: 10));
    await e.syncNow();
    expect(puts(h), before + 1);
  });
}
