// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/sync_harness.dart';

const email = 'camille@example.org', password = 'password-123';

void main() {
  late SyncHarness h;
  late AppState s;
  late String me;
  late List<int> myKey;
  final f = newId();
  late FolderKeys keys;
  late Item host;
  setUp(() async {
    h = SyncHarness();
    final acc = await h.createAccount(email, password);
    me = acc.userId;
    myKey = acc.bundle.publicKey;
    s = testAppState(harness: h);
    await s.boot();
    await s.login(server: h.baseUrl, email: email, password: password);
    h.orgMembers[testOrgId] = {me};
    keys = FolderKeys.generate(1);
    host = h.serverPutOrg(
      await sealOrgItem(keys, folderId: f, meta: hostJson('db')),
    );
  });

  Future<OrgBlock> block({
    int cursor = 1,
    String role = 'member',
    Map<String, Object?> settings = const {},
    FolderKeys? served,
    List<Map<String, Object?>> keyRequests = const [],
    List<Map<String, Object?>> extraMembers = const [],
  }) async => orgBlock(
    cursor: cursor,
    role: role,
    settings: settings,
    members: [
      memberRow(
        me,
        role: role,
        status: role == 'member' ? null : 'confirmed',
        publicKey: role == 'member' ? null : myKey,
      ),
      ...extraMembers,
    ],
    folderTree: [node(f)],
    acl: [
      aclRow(f, me, allow: ['view']),
    ],
    wrappedKeys: [await wrappedRow(served ?? keys, f, myKey, secret: false)],
    keyRequests: keyRequests,
    itemIds: [host.id],
  );

  test('a block gives keys, org entries and the org list', () async {
    h.orgBlock = await block();
    await s.sync!.syncNow();
    expect(s.orgs!.orgs.single.name, 'Acme');
    expect(s.vault!.entry(host.id)!.name, 'db');
  });

  test('an org with mascot off turns Loquet off for its members', () async {
    h.orgBlock = await block(settings: {'mascot': false});
    await s.sync!.syncNow();
    expect(s.loquet.mode, LoquetMode.off);
  });

  test('the cached block and keyring work offline after unlock', () async {
    h.orgBlock = await block();
    await s.sync!.syncNow();
    await s.lock();
    h.offline = true;
    await s.unlock(password);
    expect(
      (s.orgs!.block!.orgCursor, s.vault!.entry(host.id)!.name),
      (1, 'db'),
    );
  });

  test('refused keys raise an alert and keep the held key', () async {
    h.orgBlock = await block();
    await s.sync!.syncNow();
    h.orgBlock = await block(cursor: 2, served: FolderKeys.generate(1));
    await s.sync!.syncNow();
    expect(s.orgs!.alerts, {f});
    expect(s.vault!.entry(host.id)!.name, 'db');
  });

  test('an admin device hands off keys when a block asks', () async {
    final mia = newId(), k = await memberKeys();
    // Confirmed by the admin first.
    await s.orgs!.pins.pin(mia, k.publicKey, verified: false);
    h.orgBlock = await block(
      role: 'admin',
      extraMembers: [
        memberRow(mia, status: 'confirmed', publicKey: k.publicKey),
      ],
      keyRequests: [
        {
          'orgId': testOrgId,
          'folderId': f,
          'userId': mia,
          'version': 1,
          'secret': false,
        },
      ],
    );
    await s.sync!.syncNow();
    expect(h.orgCalls.map((c) => c.route), contains('PUT /folders/$f/keys'));
  });

  test('accepted restore keeps the keyring; lock forgets it', () async {
    h.orgBlock = await block();
    await s.sync!.syncNow();
    final g = newId();
    await s.orgs!.keyring.put(g, FolderKeys.generate(1));
    h.instanceEpoch = 'AAAAAAAAAAAAAAAAAAAAAA';
    await s.sync!.syncNow();
    await s.sync!.acceptRestore();
    expect(s.orgs!.keyring.keyFor(g, 1), isNotNull);
    await s.lock();
    expect(s.vault!.keyring, isNull);
    expect(
      s.mirror!.getKv(KvKey.keyring),
      isNotNull,
      reason: 'sealed copy stays for the next unlock',
    );
  });
}
