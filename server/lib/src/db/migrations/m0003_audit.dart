// SPDX-License-Identifier: AGPL-3.0-or-later
import '../migrations.dart';

const auditMigration = Migration(3, 'audit', [
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
]);
