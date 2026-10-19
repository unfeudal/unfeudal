// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_server/src/db/db.dart';

const t0 = '2026-10-13T12:00:00.000Z';

/// u1 (Instance Owner, device d1), u2; orgs o1 (u1 owner, u2 member in team t1 with an ACL entry and keys on f1)
/// and o2 (u2 owner); personal host ph1 with a revision; org folder f1 with host h1 (trashed, with a revision); org folder f2 in o2.
Future<void> seedSchema(Db db) async {
  for (final sql in [
    "INSERT INTO users (id, email, is_instance_owner, bundle, auth_hash, created_at) VALUES ('u1', 'u1@x.test', 1, '{}', 'h', '$t0')",
    "INSERT INTO users (id, email, bundle, auth_hash, created_at) VALUES ('u2', 'u2@x.test', '{}', 'h', '$t0')",
    "INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) VALUES ('d1', 'u1', 'n', 'linux', '$t0', '$t0')",
    "INSERT INTO refresh_tokens (token_hash, device_id, expires_at) VALUES ('rt1', 'd1', '$t0')",
    "INSERT INTO login_attempts (key, count, window_start) VALUES ('ip:1', 1, '$t0')",
    "INSERT INTO orgs (id, name, created_at) VALUES ('o1', 'Acme', '$t0')",
    "INSERT INTO orgs (id, name, created_at) VALUES ('o2', 'Beta', '$t0')",
    "INSERT INTO org_members (org_id, user_id, role, status) VALUES ('o1', 'u1', 'owner', 'confirmed')",
    "INSERT INTO org_members (org_id, user_id, role, status) VALUES ('o1', 'u2', 'member', 'confirmed')",
    "INSERT INTO org_members (org_id, user_id, role, status) VALUES ('o2', 'u2', 'owner', 'confirmed')",
    "INSERT INTO items (id, owner_user_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('ph1', 'u1', 'host', 1, '{}', 2, '$t0', '$t0', 1)",
    "INSERT INTO items (id, org_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('f1', 'o1', 'folder', 1, '{}', 2, '$t0', '$t0', 2)",
    "INSERT INTO items (id, org_id, type, folder_id, revision, deleted, body, size, created_at, updated_at, seq) VALUES ('h1', 'o1', 'host', 'f1', 1, 1, '{}', 2, '$t0', '$t0', 3)",
    "INSERT INTO items (id, org_id, type, revision, body, size, created_at, updated_at, seq) VALUES ('f2', 'o2', 'folder', 1, '{}', 2, '$t0', '$t0', 4)",
    "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES ('ph1', 0, '{}', 2, '$t0')",
    "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES ('h1', 0, '{}', 2, '$t0')",
    "INSERT INTO teams (id, org_id, name) VALUES ('t1', 'o1', 'Ops')",
    "INSERT INTO team_members (org_id, team_id, user_id) VALUES ('o1', 't1', 'u2')",
    "INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) VALUES ('o1', 'f1', 'user', 'u2', '[\"view\"]', '[]')",
    "INSERT INTO folder_keys (org_id, folder_id, user_id, version, meta_wrapped) VALUES ('o1', 'f1', 'u2', 1, 'w')",
    "INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES ('o1', 'f1', 1, '{}')",
    "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES ('o1', 'f1', 'member_removed', '[]')",
    "INSERT INTO invites (id, token_hash, email, org_id, role, created_by, created_at, expires_at) VALUES ('i1', 'th1', 'x@x.test', 'o1', 'member', 'u1', '$t0', '$t0')",
    "INSERT INTO audit_events (scope, seq, ts, action, target_ids, prev_hash, hash) VALUES ('instance', 1, '$t0', 'setup.completed', '[]', '0', 'h')",
  ]) {
    await db.execute(sql);
  }
}
