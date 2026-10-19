// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';

import '../support/schema_world.dart';
import '../support/test_db.dart';

/// (deletion rule, statements that run first, statement that must fail).
const outOfOrder = [
  (
    'removing a member: the membership cannot go before team seats and keys',
    <String>[],
    "DELETE FROM org_members WHERE org_id = 'o1' AND user_id = 'u2'",
  ),
  (
    'removing a member: the membership cannot go before folder keys',
    ["DELETE FROM team_members WHERE user_id = 'u2'"],
    "DELETE FROM org_members WHERE org_id = 'o1' AND user_id = 'u2'",
  ),
  (
    'deleting a team: the team cannot go before its seats',
    <String>[],
    "DELETE FROM teams WHERE id = 't1'",
  ),
  (
    'purging an org folder: not while ACL entries point to it',
    <String>[],
    "DELETE FROM items WHERE id = 'f1'",
  ),
  (
    'purging an org folder: not while keys point to it',
    ["DELETE FROM acl_entries WHERE folder_id = 'f1'"],
    "DELETE FROM items WHERE id = 'f1'",
  ),
  (
    'purging an org folder: not while its key history exists',
    [
      "DELETE FROM acl_entries WHERE folder_id = 'f1'",
      "DELETE FROM folder_keys WHERE folder_id = 'f1'",
    ],
    "DELETE FROM items WHERE id = 'f1'",
  ),
  (
    'purging an org folder: not while a rotation is pending',
    [
      "DELETE FROM acl_entries WHERE folder_id = 'f1'",
      "DELETE FROM folder_keys WHERE folder_id = 'f1'",
      "DELETE FROM folder_key_history WHERE folder_id = 'f1'",
    ],
    "DELETE FROM items WHERE id = 'f1'",
  ),
  (
    'deleting an org: the org cannot go before its members, teams, items and invites',
    <String>[],
    "DELETE FROM orgs WHERE id = 'o1'",
  ),
  (
    'deleting an org: items cannot go before their revisions',
    <String>[],
    "DELETE FROM items WHERE id = 'h1'",
  ),
  (
    'deleting an org: members cannot go before team seats',
    <String>[],
    "DELETE FROM org_members WHERE org_id = 'o1'",
  ),
  (
    'moving the Instance Owner: the new owner cannot be set before the old one is cleared',
    <String>[],
    "UPDATE users SET is_instance_owner = 1 WHERE id = 'u2'",
  ),
  (
    'deleting a user: the user cannot go before devices',
    <String>[],
    "DELETE FROM users WHERE id = 'u1'",
  ),
  (
    'deleting a user: devices cannot go before refresh tokens',
    <String>[],
    "DELETE FROM devices WHERE id = 'd1'",
  ),
  (
    'deleting a user: personal items cannot go before their revisions',
    <String>[],
    "DELETE FROM items WHERE id = 'ph1'",
  ),
  (
    'deleting a user: the user cannot go before memberships',
    ["DELETE FROM team_members", "DELETE FROM folder_keys"],
    "DELETE FROM users WHERE id = 'u2'",
  ),
];

void main() {
  late Db db;
  setUp(() async {
    db = await openTestDb();
    await migrate(db);
    await seedSchema(db);
  });
  tearDown(() => db.close());

  for (final (name, before, blocked) in outOfOrder) {
    test(name, () async {
      for (final sql in before) {
        await db.execute(sql);
      }
      await expectLater(db.execute(blocked), throwsA(anything));
    });
  }

  test('moving the Instance Owner: old to 0 then new to 1 succeeds', () async {
    await db.transaction((tx) async {
      await tx.execute(
        'UPDATE users SET is_instance_owner = 0 WHERE is_instance_owner = 1',
      );
      await tx.execute(
        "UPDATE users SET is_instance_owner = 1 WHERE id = 'u2'",
      );
    });
    expect(
      (await db.query('SELECT id FROM users WHERE is_instance_owner = 1'))
          .single['id'],
      'u2',
    );
  });
}
