// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';

import '../support/schema_world.dart';
import '../support/test_db.dart';

const timeColumns = [
  ('users', 'created_at'),
  ('devices', 'created_at'),
  ('devices', 'last_seen_at'),
  ('devices', 'revoked_at'),
  ('refresh_tokens', 'expires_at'),
  ('refresh_tokens', 'used_at'),
  ('login_attempts', 'window_start'),
  ('login_attempts', 'locked_until'),
  ('orgs', 'created_at'),
  ('items', 'created_at'),
  ('items', 'updated_at'),
  ('item_revisions', 'created_at'),
  ('invites', 'created_at'),
  ('invites', 'expires_at'),
  ('invites', 'accepted_at'),
  ('invites', 'revoked_at'),
  ('audit_events', 'ts'),
];

const refused = {
  'users.email is unique':
      "INSERT INTO users (id, email, bundle, auth_hash, created_at) VALUES ('u9', 'u1@x.test', '{}', 'h', '$t0')",
  'one Instance Owner at most':
      "UPDATE users SET is_instance_owner = 1 WHERE id = 'u2'",
  'devices.user_id → users':
      "INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) VALUES ('d9', 'nobody', 'n', 'linux', '$t0', '$t0')",
  'refresh_tokens.device_id → devices':
      "INSERT INTO refresh_tokens (token_hash, device_id, expires_at) VALUES ('rt9', 'nobody', '$t0')",
  'items: neither personal nor org':
      "INSERT INTO items (id, type, revision, body, size, created_at, updated_at, seq) VALUES ('x1', 'host', 1, '{}', 2, '$t0', '$t0', 9)",
  'items: both personal and org':
      "INSERT INTO items (id, owner_user_id, org_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('x2', 'u1', 'o1', 'folder', 1, '{}', 2, '$t0', '$t0', 9)",
  'org item outside a folder':
      "INSERT INTO items (id, org_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('x3', 'o1', 'host', 1, '{}', 2, '$t0', '$t0', 9)",
  'items.owner_user_id → users':
      "INSERT INTO items (id, owner_user_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('x4', 'nobody', 'host', 1, '{}', 2, '$t0', '$t0', 9)",
  'items.org_id → orgs':
      "INSERT INTO items (id, org_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('x5', 'nobody', 'folder', 1, '{}', 2, '$t0', '$t0', 9)",
  'item_revisions.item_id → items':
      "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES ('nobody', 0, '{}', 2, '$t0')",
  'item_revisions key (item, revision)':
      "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES ('ph1', 0, '{}', 2, '$t0')",
  'org_members.org_id → orgs': "INSERT INTO org_members (org_id, user_id, role, status) VALUES ('nobody', 'u1', 'owner', 'confirmed')",
  'org_members.user_id → users': "INSERT INTO org_members (org_id, user_id, role, status) VALUES ('o2', 'nobody', 'member', 'confirmed')",
  'org_members key (org, user)': "INSERT INTO org_members (org_id, user_id, role, status) VALUES ('o1', 'u2', 'admin', 'confirmed')",
  'teams.org_id → orgs':
      "INSERT INTO teams (id, org_id, name) VALUES ('t9', 'nobody', 'X')",
  'team names are unique per org':
      "INSERT INTO teams (id, org_id, name) VALUES ('t9', 'o1', 'Ops')",
  'team_members: team of another org': "INSERT INTO team_members (org_id, team_id, user_id) VALUES ('o2', 't1', 'u2')",
  'team_members: seat needs a membership': "INSERT INTO team_members (org_id, team_id, user_id) VALUES ('o1', 't1', 'nobody')",
  'acl_entries: folder of another org': "INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) VALUES ('o1', 'f2', 'user', 'u2', '[]', '[]')",
  'acl_entries key (folder, principal)': "INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) VALUES ('o1', 'f1', 'user', 'u2', '[]', '[]')",
  'folder_keys: holder must be a member': "INSERT INTO folder_keys (org_id, folder_id, user_id, version, meta_wrapped) VALUES ('o1', 'f1', 'nobody', 1, 'w')",
  'folder_keys: folder of another org': "INSERT INTO folder_keys (org_id, folder_id, user_id, version, meta_wrapped) VALUES ('o2', 'f1', 'u2', 1, 'w')",
  'folder_key_history → org folder': "INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES ('o1', 'nobody', 1, '{}')",
  'pending_rotations → org folder': "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES ('o1', 'nobody', 'acl_change', '[]')",
  'invites.org_id → orgs':
      "INSERT INTO invites (id, token_hash, email, org_id, created_by, created_at, expires_at) VALUES ('i9', 'th9', 'x@x.test', 'nobody', 'u1', '$t0', '$t0')",
  'invite token hashes are unique':
      "INSERT INTO invites (id, token_hash, email, created_by, created_at, expires_at) VALUES ('i9', 'th1', 'x@x.test', 'u1', '$t0', '$t0')",
  'audit_events key (scope, seq)':
      "INSERT INTO audit_events (scope, seq, ts, action, target_ids, prev_hash, hash) VALUES ('instance', 1, '$t0', 'x', '[]', '0', 'h')",
  'counters.name is unique':
      "INSERT INTO counters (name, value) VALUES ('items_seq', 5)",
};

void main() {
  late Db db;
  setUp(() async {
    db = await openTestDb();
    await migrate(db);
    await seedSchema(db);
  });
  tearDown(() => db.close());

  test(
    'the seed is valid and a 24-character time is accepted everywhere',
    () async {
      for (final (table, column) in timeColumns) {
        await db.execute('UPDATE $table SET $column = @v', {'v': t0});
      }
    },
  );

  for (final (table, column) in timeColumns) {
    test('$table.$column must be 24 characters', () async {
      await expectLater(
        db.execute("UPDATE $table SET $column = '2026-10-13T12:00:00Z'"),
        throwsA(anything),
      );
    });
  }

  for (final MapEntry(key: name, value: sql) in refused.entries) {
    test(name, () async {
      await expectLater(db.execute(sql), throwsA(anything));
    });
  }
}
