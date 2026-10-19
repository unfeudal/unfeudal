// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/orgs/org_access.dart';
import 'package:unfeudal_server/src/orgs/rotations.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/matchers.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'mia': 'member', 'max': 'member', 'kim': 'member'},
      teams: {
        'Ops': ['mia', 'max'],
      },
      folders: {'prod': null, 'db': 'prod', 'new': null},
    );
    await w.acl('prod', 'team:Ops', allow: ['view', 'connect']);
    await w.keys('prod', 1, ['olivia', 'mia', 'max']);
    await w.keys('db', 1, ['olivia', 'mia', 'max']);
  });
  tearDown(() => s.close());

  Future<OrgSnapshot> snap() async =>
      (await s.db.transaction<OrgSnapshot?>((tx) => loadOrg(tx, w.orgId)))!;
  Future<void> record(OrgSnapshot before, String reason) => s.db.transaction(
    (tx) async => recordRotations(
      tx,
      w.orgId,
      before,
      (await loadOrg(tx, w.orgId))!,
      reason,
    ),
  );
  Future<Map<String, Map<String, Object?>>> pending() async => {
    for (final r in await s.db.query(
      'SELECT folder_id, reason, removed_user_ids, rotated_version FROM pending_rotations',
    ))
      r['folder_id']! as String: r,
  };
  List<Object?> ids(Map<String, Object?> row) =>
      jsonDecode(row['removed_user_ids']! as String) as List<Object?>;

  test('a lost view or connect records one row per keyed folder; gains and unkeyed folders record nothing', () async {
    final before = await snap();
    await s.db.execute('DELETE FROM team_members WHERE user_id = @u', {
      'u': w.id('mia'),
    });
    await w.acl('new', 'user:kim', allow: ['view']);
    await record(before, 'team_change');
    final rows = await pending();
    expect(rows.keys.toSet(), {w.folder('prod'), w.folder('db')});
    expect(
      rows.values.every(
        (r) => r['reason'] == 'team_change' && r['rotated_version'] == null,
      ),
      isTrue,
    );
    expect(ids(rows[w.folder('prod')]!), [w.id('mia')]);
  });

  test('losing connect only counts; a new removal merges sorted ids and resets rotated_version', () async {
    var before = await snap();
    await s.db.execute('''UPDATE acl_entries SET allow = '["view"]' ''');
    await record(before, 'acl_change');
    final both = [w.id('mia'), w.id('max')]..sort();
    expect(ids((await pending())[w.folder('prod')]!), both);
    await s.db.execute('UPDATE pending_rotations SET rotated_version = 2');
    await w.acl('prod', 'user:kim', allow: ['view']);
    before = await snap();
    await s.db.execute("DELETE FROM acl_entries WHERE principal_type = 'user'");
    await record(before, 'acl_change');
    final row = (await pending())[w.folder('prod')]!;
    expect((row['reason'], row['rotated_version']), ('acl_change', null));
    expect(ids(row), [...both, w.id('kim')]..sort());
  });

  test(
    'checkNoEscalation: any gain must be held by the caller on that folder',
    () async {
      await w.acl(
        'prod',
        'user:max',
        allow: ['manage', 'edit', 'view', 'connect'],
      );
      final before = await snap();
      await w.acl('db', 'user:kim', allow: ['reveal']);
      final after = await snap();
      expect(
        () => checkNoEscalation(before, after, w.id('max')),
        throwsApi(ApiErrorCode.forbidden),
        reason: 'max lacks reveal',
      );
      checkNoEscalation(before, after, w.id('olivia'));
      checkNoEscalation(after, after, w.id('max'));
    },
  );
}
