// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/sync_harness.dart';

void main() {
  test('no common API: read-only, no push and no pull', () async {
    final h = SyncHarness(api: [2]);
    final (e, m, _) = await h.engine();
    m.enqueue(wireItem(newId(), revision: 0), baseRevision: 0);
    await e.syncNow();
    expect((e.readOnly, e.compat!.reason), (true, 'no-common-api'));
    expect(h.requests.where((r) => r.contains('/api/v1/')), isEmpty);
    await expectLater(
      e.write(wireItem(newId(), revision: 0)),
      throwsA(isA<ReadOnlyException>()),
    );
  });

  test('client too old: pull only', () async {
    final h = SyncHarness(minClient: '9.0.0');
    final (e, m, _) = await h.engine();
    h.serverPut(wireItem(newId(), revision: 0));
    m.enqueue(wireItem(newId(), revision: 0), baseRevision: 0);
    await e.syncNow();
    expect((e.readOnly, e.compat!.reason), (true, 'client-too-old'));
    expect(m.items(), hasLength(1));
    expect(h.requests.where((r) => r.startsWith('PUT ')), isEmpty);
  });

  test('client_too_old on a write switches to read-only', () async {
    final h = SyncHarness(
      minClient: '9.0.0',
      infoExtra: {'minClient': '0.1.0'},
    ); // info still says compatible
    final (e, m, _) = await h.engine();
    await e.write(wireItem(newId(), revision: 0));
    await e.syncNow();
    expect(e.readOnly, true);
    expect(e.compat!.reason, 'client-too-old');
    expect(m.outbox(), hasLength(1));
  });

  test('update notice from latestClient only', () async {
    final h = SyncHarness(latestClient: '0.2.0');
    final (e, _, _) = await h.engine();
    await e.syncNow();
    expect(e.updateNotice!.version, '0.2.0');
    h.latestClient = '0.1.0';
    await e.syncNow();
    expect(e.updateNotice, isNull);
  });

  test('a compatible server again lifts read-only', () async {
    final h = SyncHarness(minClient: '9.0.0');
    final (e, _, _) = await h.engine();
    await e.syncNow();
    expect(e.readOnly, isTrue);
    h.minClient = '0.1.0';
    await e.syncNow();
    expect(e.readOnly, isFalse);
  });
}
