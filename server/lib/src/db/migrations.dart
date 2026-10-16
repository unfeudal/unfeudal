// SPDX-License-Identifier: AGPL-3.0-or-later

class Migration {
  const Migration(this.version, this.name, this.statements);
  final int version;
  final String name;
  final List<String> statements;
}

/// Server schema, one statement per string. A released entry is never edited:
/// a change is a new entry.
const migrations = <Migration>[
  Migration(1, 'core', [
    r"""CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL)""",
    r"""CREATE TABLE users (
  id                 TEXT PRIMARY KEY,
  email              TEXT NOT NULL UNIQUE,
  is_instance_owner  INTEGER NOT NULL DEFAULT 0,
  disabled           INTEGER NOT NULL DEFAULT 0,
  bundle             TEXT NOT NULL,
  bundle_version     BIGINT NOT NULL DEFAULT 0,
  auth_hash          TEXT NOT NULL,
  recovery_auth_hash TEXT,
  created_at         TEXT NOT NULL CHECK (length(created_at) = 24))""",
    r"""CREATE UNIQUE INDEX users_one_instance_owner ON users (is_instance_owner) WHERE is_instance_owner = 1""",
    r"""CREATE TABLE devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id),
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL,
  created_at   TEXT NOT NULL CHECK (length(created_at) = 24),
  last_seen_at TEXT NOT NULL CHECK (length(last_seen_at) = 24),
  revoked_at   TEXT CHECK (length(revoked_at) = 24))""",
    r"""CREATE INDEX devices_user ON devices (user_id)""",
    r"""CREATE TABLE refresh_tokens (
  token_hash TEXT PRIMARY KEY,
  device_id  TEXT NOT NULL REFERENCES devices(id),
  expires_at TEXT NOT NULL CHECK (length(expires_at) = 24),
  used_at    TEXT CHECK (length(used_at) = 24))""",
    r"""CREATE INDEX refresh_tokens_device ON refresh_tokens (device_id)""",
    r"""CREATE TABLE login_attempts (
  key          TEXT PRIMARY KEY,
  count        BIGINT NOT NULL,
  window_start TEXT NOT NULL CHECK (length(window_start) = 24),
  locked_until TEXT CHECK (length(locked_until) = 24))""",
    r"""CREATE TABLE counters (
  name  TEXT PRIMARY KEY,
  value BIGINT NOT NULL)""",
    r"""INSERT INTO counters (name, value) VALUES ('items_seq', 0)""",
    r"""CREATE TABLE orgs (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  settings   TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL CHECK (length(created_at) = 24))""",
    r"""CREATE TABLE items (
  id            TEXT PRIMARY KEY,
  owner_user_id TEXT REFERENCES users(id),
  org_id        TEXT REFERENCES orgs(id),
  type          TEXT NOT NULL,
  folder_id     TEXT,
  revision      BIGINT NOT NULL,
  deleted       INTEGER NOT NULL DEFAULT 0,
  purged        INTEGER NOT NULL DEFAULT 0,
  body          TEXT NOT NULL,
  size          BIGINT NOT NULL,
  created_at    TEXT NOT NULL CHECK (length(created_at) = 24),
  updated_at    TEXT NOT NULL CHECK (length(updated_at) = 24),
  seq           BIGINT NOT NULL,
  CHECK ((owner_user_id IS NULL) <> (org_id IS NULL)),
  CHECK (org_id IS NULL OR type = 'folder' OR folder_id IS NOT NULL),
  UNIQUE (org_id, id))""",
    r"""CREATE INDEX items_owner_seq ON items (owner_user_id, seq)""",
    r"""CREATE INDEX items_trash ON items (updated_at) WHERE deleted = 1 AND purged = 0""",
    r"""CREATE TABLE item_revisions (
  item_id    TEXT NOT NULL REFERENCES items(id),
  revision   BIGINT NOT NULL,
  body       TEXT NOT NULL,
  size       BIGINT NOT NULL,
  created_at TEXT NOT NULL CHECK (length(created_at) = 24),
  PRIMARY KEY (item_id, revision))""",
  ]),
  Migration(2, 'orgs', [
    r"""CREATE TABLE org_members (
  org_id     TEXT NOT NULL REFERENCES orgs(id),
  user_id    TEXT NOT NULL REFERENCES users(id),
  role       TEXT NOT NULL,
  status     TEXT NOT NULL,
  PRIMARY KEY (org_id, user_id))""",
    r"""CREATE INDEX org_members_user ON org_members (user_id)""",
    r"""CREATE TABLE teams (
  id     TEXT PRIMARY KEY,
  org_id TEXT NOT NULL REFERENCES orgs(id),
  name   TEXT NOT NULL,
  UNIQUE (org_id, id),
  UNIQUE (org_id, name))""",
    r"""CREATE TABLE team_members (
  org_id  TEXT NOT NULL,
  team_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  PRIMARY KEY (team_id, user_id),
  FOREIGN KEY (org_id, team_id) REFERENCES teams(org_id, id),
  FOREIGN KEY (org_id, user_id) REFERENCES org_members(org_id, user_id))""",
    r"""CREATE INDEX team_members_user ON team_members (user_id)""",
    r"""CREATE TABLE acl_entries (
  org_id         TEXT NOT NULL REFERENCES orgs(id),
  folder_id      TEXT NOT NULL,
  principal_type TEXT NOT NULL,
  principal_id   TEXT NOT NULL,
  allow          TEXT NOT NULL,
  deny           TEXT NOT NULL,
  PRIMARY KEY (folder_id, principal_type, principal_id),
  FOREIGN KEY (org_id, folder_id) REFERENCES items(org_id, id))""",
    r"""CREATE INDEX acl_entries_org ON acl_entries (org_id)""",
    r"""CREATE INDEX acl_entries_principal ON acl_entries (principal_type, principal_id)""",
    r"""CREATE TABLE folder_keys (
  org_id         TEXT NOT NULL,
  folder_id      TEXT NOT NULL,
  user_id        TEXT NOT NULL,
  version        BIGINT NOT NULL,
  meta_wrapped   TEXT NOT NULL,
  secret_wrapped TEXT,
  PRIMARY KEY (folder_id, user_id),
  FOREIGN KEY (org_id, folder_id) REFERENCES items(org_id, id),
  FOREIGN KEY (org_id, user_id) REFERENCES org_members(org_id, user_id))""",
    r"""CREATE INDEX folder_keys_user ON folder_keys (user_id)""",
    r"""CREATE TABLE folder_key_history (
  org_id    TEXT NOT NULL,
  folder_id TEXT PRIMARY KEY,
  version   BIGINT NOT NULL,
  body      TEXT NOT NULL,
  FOREIGN KEY (org_id, folder_id) REFERENCES items(org_id, id))""",
    r"""CREATE TABLE invites (
  id          TEXT PRIMARY KEY,
  token_hash  TEXT NOT NULL UNIQUE,
  email       TEXT NOT NULL,
  org_id      TEXT REFERENCES orgs(id),
  role        TEXT,
  created_by  TEXT NOT NULL,
  created_at  TEXT NOT NULL CHECK (length(created_at) = 24),
  expires_at  TEXT NOT NULL CHECK (length(expires_at) = 24),
  accepted_at TEXT CHECK (length(accepted_at) = 24),
  revoked_at  TEXT CHECK (length(revoked_at) = 24))""",
    r"""CREATE INDEX invites_org ON invites (org_id)""",
    r"""CREATE TABLE pending_rotations (
  org_id           TEXT NOT NULL,
  folder_id        TEXT PRIMARY KEY,
  reason           TEXT NOT NULL,
  removed_user_ids TEXT NOT NULL,
  rotated_version  BIGINT,
  FOREIGN KEY (org_id, folder_id) REFERENCES items(org_id, id))""",
    r"""CREATE INDEX items_org_folder_seq ON items (org_id, folder_id, seq)""",
    r"""INSERT INTO counters (name, value) VALUES ('org_seq', 0)""",
  ]),
  Migration(3, 'audit', [
    r"""CREATE TABLE audit_events (
  scope        TEXT NOT NULL,
  seq          BIGINT NOT NULL,
  ts           TEXT NOT NULL CHECK (length(ts) = 24),
  actor_user   TEXT,
  actor_device TEXT,
  ip           TEXT,
  action       TEXT NOT NULL,
  target_ids   TEXT NOT NULL,
  prev_hash    TEXT NOT NULL,
  hash         TEXT NOT NULL,
  PRIMARY KEY (scope, seq))""",
    r"""CREATE INDEX audit_events_actor ON audit_events (actor_user, ts)""",
    r"""CREATE TABLE audit_heads (
  scope TEXT PRIMARY KEY,
  seq   BIGINT NOT NULL,
  hash  TEXT NOT NULL)""",
    r"""CREATE TABLE audit_ips (
  scope TEXT NOT NULL,
  seq   BIGINT NOT NULL,
  ip    TEXT NOT NULL,
  PRIMARY KEY (scope, seq))""",
  ]),
  Migration(4, 'locale', [
    r"""ALTER TABLE users ADD COLUMN locale TEXT NOT NULL DEFAULT 'en'""",
  ]),
];
