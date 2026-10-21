// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/sync_engine.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';
import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  late LocalMirror m;
  late SyncEngine e;
  late FolderKeys keys;
  final f = newId();
  final blocks = <OrgBlock>[];
  setUp(() async {
    h = SyncHarness();
    final login = await h.signIn();
    h.orgMembers[testOrgId] = {login.account.userId};
    m = LocalMirror.inMemory();
    final api = ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken;
    e = SyncEngine(api: api, mirror: m, deviceId: login.deviceId)
      ..onOrgBlock = (b) async => blocks.add(b);
    keys = FolderKeys.generate(1);
    blocks.clear();
  });

  Future<Item> serverOrgItem({String? id}) async => h.serverPutOrg(
    await sealOrgItem(keys, id: id, folderId: f, meta: {'name': 'h'}),
  );

  test('a block arriving calls onOrgBlock after the page is applied', () async {
    final a = await serverOrgItem();
    h.orgBlock = orgBlock(itemIds: [a.id]);
    await e.syncNow();
    expect((m.item(a.id)?.id, blocks.single.orgCursor), (a.id, 1));
    await e.syncNow();
    expect(blocks, hasLength(1), reason: 'no new block, no call');
  });

  test('itemIds rule deletes only absent ids held before the block; queued ids stay', () async {
    final a = await serverOrgItem(),
        b = await serverOrgItem(),
        queued = await serverOrgItem();
    h.orgBlock = orgBlock(itemIds: [a.id, b.id, queued.id]);
    await e.syncNow();
    m.enqueue(queued, baseRevision: 1);
    h.failPuts[queued.id] = 403; // stays queued through the round
    // The server stopped showing b and queued.
    h.orgBlock = orgBlock(cursor: 2, itemIds: [a.id]);
    await e.syncNow();
    expect(m.item(b.id), isNull);
    expect((m.item(a.id)?.id, m.item(queued.id)?.id), (a.id, queued.id));
  });

  test(
    'an id missing locally triggers one resync from cursor 0, never a loop',
    () async {
      final a = await serverOrgItem();
      h.orgBlock = orgBlock(itemIds: [a.id]);
      await e.syncNow();
      final ghost = newId();
      h.orgBlock = orgBlock(cursor: 2, itemIds: [a.id, ghost]);
      h.requests.clear();
      await e.syncNow();
      final pulls = h.requests.where((r) => r == 'GET /api/v1/sync').length;
      expect(pulls, 2, reason: 'the round, then one full resync');
      expect(m.item(a.id), isNotNull);
    },
  );

  test(
    'items of later pages in the same pull are not judged by the block',
    () async {
      h.pageSize = 1;
      final a = await serverOrgItem();
      // Written after the block snapshot: page 2, seq above page 1's cursor.
      final later = await serverOrgItem();
      h.orgBlock = orgBlock(itemIds: [a.id]);
      await e.syncNow();
      expect((m.item(a.id)?.id, m.item(later.id)?.id), (a.id, later.id));
    },
  );

  test('a cached block is never used for the rule; personal items are never judged', () async {
    final a = await serverOrgItem();
    h.orgBlock = orgBlock(itemIds: [a.id]);
    await e.syncNow();
    h.orgBlock = null;
    h.serverPut(
      Item.fromJson({
        ...a.toJson(),
        'id': newId(),
        'scope': 'personal',
        'orgId': null,
        'folderId': null,
      }),
      email: h.accounts.keys.first,
    );
    await e.syncNow();
    expect(m.items(), hasLength(2));
  });
}
