// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' hide Version;
import 'package:unfeudal_shared/unfeudal_shared.dart';

/// The mirror file was written by a newer client; it is left untouched.
class MirrorTooNew implements Exception {
  const MirrorTooNew(this.found);
  final int found;

  @override
  String toString() => 'MirrorTooNew: user_version $found';
}

enum OutboxState { pending, rejected }

class OutboxEntry {
  const OutboxEntry(
    this.item,
    this.baseRevision,
    this.state,
    this.attempts,
    this.lastError,
  );

  final Item item;
  final int baseRevision;
  final OutboxState state;
  final int attempts;
  final String? lastError;
}

enum KvKey {
  cursor,
  bundle,
  apiInfo,
  refusedEpoch,
  ledger,
  orgCursor,
  orgBlock,
  keyring,
  anchors,
}

/// Local SQLite mirror of one account: confirmed server items, the outbox of local writes, and a key-value table.
class LocalMirror {
  LocalMirror._(this._db) {
    final version =
        _db.select('PRAGMA user_version').single.values.single! as int;
    if (version > _schemaVersion) {
      _db.close();
      throw MirrorTooNew(version);
    }
    if (version == 0) {
      _transaction(() {
        for (final statement in _schema) {
          _db.execute(statement);
        }
        _db.execute('PRAGMA user_version = $_schemaVersion');
      });
    }
  }

  factory LocalMirror.open(String path) => LocalMirror._(sqlite3.open(path));

  factory LocalMirror.inMemory() => LocalMirror._(sqlite3.openInMemory());

  static const _schemaVersion = 1;

  // schema version 1; a later version only adds tables, nullable columns or indexes
  static const _schema = [
    'CREATE TABLE items (id TEXT PRIMARY KEY, json TEXT NOT NULL)',
    '''
CREATE TABLE outbox (
  item_id       TEXT PRIMARY KEY,
  json          TEXT NOT NULL,
  base_revision INTEGER NOT NULL,
  state         TEXT NOT NULL DEFAULT 'pending',
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT)''',
    '''
CREATE TABLE kv (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL)''',
  ];

  final Database _db;

  List<Item> items() => [
    for (final r in _db.select('SELECT json FROM items')) _item(r),
  ];

  Item? item(String id) {
    final rows = _db.select('SELECT json FROM items WHERE id = ?', [id]);
    return rows.isEmpty ? null : _item(rows.single);
  }

  /// Server items. Returns how many were ignored as older than the stored revision (rollback guard);
  /// `acceptOlder` only for the full pull of an accepted server restore.
  int upsertItems(Iterable<Item> items, {bool acceptOlder = false}) {
    var ignored = 0;
    _transaction(() {
      for (final it in items) {
        final current = item(it.id);
        if (!acceptOlder &&
            current != null &&
            (it.revision ?? 0) < (current.revision ?? 0)) {
          ignored++;
          continue;
        }
        _db.execute(
          'INSERT INTO items (id, json) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json',
          [it.id, jsonEncode(it.toJson())],
        );
      }
    });
    return ignored;
  }

  void deleteItems(Iterable<String> ids) => _transaction(() {
    for (final id in ids) {
      _db.execute('DELETE FROM items WHERE id = ?', [id]);
    }
  });

  String? getKv(KvKey key) {
    final rows = _db.select('SELECT value FROM kv WHERE key = ?', [key.name]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  void setKv(KvKey key, String? value) => value == null
      ? _db.execute('DELETE FROM kv WHERE key = ?', [key.name])
      : _db.execute(
          'INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key.name, value],
        );

  List<OutboxEntry> outbox() => [
    for (final r in _db.select(
      'SELECT json, base_revision, state, attempts, last_error FROM outbox ORDER BY rowid',
    ))
      OutboxEntry(
        _item(r),
        r['base_revision'] as int,
        OutboxState.values.byName(r['state'] as String),
        r['attempts'] as int,
        r['last_error'] as String?,
      ),
  ];

  /// Local write. A second edit of a queued item keeps its first base revision and position, and makes a
  /// rejected entry pending again.
  void enqueue(Item item, {required int baseRevision}) => _db.execute(
    'INSERT INTO outbox (item_id, json, base_revision) VALUES (?, ?, ?) '
    "ON CONFLICT(item_id) DO UPDATE SET json = excluded.json, state = 'pending', attempts = 0, last_error = NULL",
    [item.id, jsonEncode(item.toJson()), baseRevision],
  );

  /// Returns the attempt count after this failure.
  int recordOutboxFailure(String itemId, String error) =>
      _db.select(
            'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE item_id = ? RETURNING attempts',
            [error, itemId],
          ).single['attempts']
          as int;

  void rejectOutbox(String itemId) => _db.execute(
    "UPDATE outbox SET state = 'rejected' WHERE item_id = ?",
    [itemId],
  );

  void retryOutbox(String itemId) => _db.execute(
    "UPDATE outbox SET state = 'pending', attempts = 0, last_error = NULL WHERE item_id = ?",
    [itemId],
  );

  void rebaseOutbox(String itemId, int baseRevision) => _db.execute(
    'UPDATE outbox SET base_revision = ? WHERE item_id = ?',
    [baseRevision, itemId],
  );

  void removeOutbox(String itemId) =>
      _db.execute('DELETE FROM outbox WHERE item_id = ?', [itemId]);

  /// Full resync: items stay until the full pull replaces them; outbox kept.
  void resetForResync() =>
      _deleteKv([KvKey.cursor, KvKey.orgCursor, KvKey.orgBlock]);

  /// Accepted server restore: as a resync, and the audit anchors go. Pins and keyring stay; the
  /// anti-replay marks are emptied by `LedgerStore.reset`.
  void resetForRestore() =>
      _deleteKv([KvKey.cursor, KvKey.orgCursor, KvKey.orgBlock, KvKey.anchors]);

  void close() => _db.close();

  void _deleteKv(List<KvKey> keys) => _transaction(() {
    for (final k in keys) {
      setKv(k, null);
    }
  });

  Item _item(Row row) => Item.fromJson(jsonDecode(row['json'] as String));

  void _transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
