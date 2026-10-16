// SPDX-License-Identifier: AGPL-3.0-or-later
import '../migrations.dart';

const coreMigration = Migration(1, 'core', [
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
]);
