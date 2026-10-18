// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../storage/local_mirror.dart';
import '../version.dart';

/// Push the outbox, pull the server's changes: at start, after each local change, every [interval].
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.api,
    required this.mirror,
    required this.deviceId,
    this.version = clientVersion,
    this.apis = clientApis,
    this.interval = const Duration(seconds: 30),
    this._now = DateTime.now,
  });

  final ApiClient api;
  final LocalMirror mirror;
  final String deviceId;
  final String version;
  final List<int> apis;
  final Duration interval;
  final DateTime Function() _now;

  static const maxAttempts = 3;

  /// Conflict copy of a local write (the vault seals it).
  Future<Item?> Function(Item mine, {required bool personal})? copyOf;

  /// The local view must be rebuilt (the vault reloads).
  Future<void> Function()? onChanged;
  void Function(String? reason)? onUnauthorized;

  bool online = true;
  Object? lastError;
  DateTime? lastSyncAt;
  int ignoredRollbacks = 0;
  Compat? compat;

  bool get readOnly => compat?.mode == CompatMode.readOnly;

  Timer? _timer;
  Future<void>? _running;
  bool _again = false;

  void start() {
    unawaited(syncNow());
    _timer ??= Timer.periodic(interval, (_) => unawaited(syncNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One round at a time; a call during a round schedules one more, and resolves after it.
  Future<void> syncNow() => _single(_round);

  Future<void> write(Item item) async {
    if (readOnly) throw ReadOnlyException(compat?.reason);
    mirror.enqueue(item, baseRevision: item.revision ?? 0);
    unawaited(syncNow());
  }

  Future<void> _single(Future<void> Function() first) {
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = () async {
      try {
        for (var next = first; ; next = _round) {
          _again = false;
          await next();
          if (!_again) break;
        }
      } finally {
        _running = null;
      }
    }();
  }

  Future<void> _round() async {
    try {
      final info = await api.info();
      online = true;
      if (!_negotiate(info)) return;
      if (compat!.mode == CompatMode.full) {
        await _push(); // client-too-old: pull only
      }
      await _pull();
      mirror.setKv(KvKey.apiInfo, jsonEncode(info.toJson()));
      lastSyncAt = _now();
      lastError = null;
    } on NetworkException catch (e) {
      online = false;
      lastError = e;
    } on ApiException catch (e) {
      if (e.status == 401) {
        onUnauthorized?.call(e.reason);
      } else {
        lastError = e;
      }
    } on FormatException catch (e) {
      lastError = e; // protocol error: shown in the sync banner, retried next round; nothing deleted
    } on ReadOnlyException catch (e) {
      lastError = e; // read-only switched on during the round; nothing lost, the outbox stays
    } finally {
      await onChanged?.call();
      notifyListeners();
    }
  }

  /// False when there is no common API: no push, no pull.
  bool _negotiate(ApiInfo info) {
    compat = negotiate(version, apis, info);
    api.readOnly = readOnly;
    return compat!.api != null;
  }

  Future<void> _pull() async {
    var cursor = int.parse(mirror.getKv(KvKey.cursor) ?? '0');
    var orgCursor = int.parse(mirror.getKv(KvKey.orgCursor) ?? '0');
    for (var more = true; more;) {
      final page = await api.sync(
        cursor: cursor,
        orgCursor: orgCursor,
      ); // parsed whole before anything is applied
      ignoredRollbacks += mirror.upsertItems(page.items);
      if (page.org case final org?) {
        mirror
          ..setKv(KvKey.orgBlock, jsonEncode(org.toJson()))
          ..setKv(KvKey.orgCursor, '${org.orgCursor}'); // itemIds rule: p6
        orgCursor = org.orgCursor;
      }
      cursor = page.cursor;
      mirror.setKv(KvKey.cursor, '$cursor');
      more = page.more;
    }
  }

  Future<void> _push() async {
    for (final e in mirror.outbox().where(
      (e) => e.state == OutboxState.pending,
    )) {
      try {
        _settle(e.item, await api.putItem(e.item, ifMatch: e.baseRevision));
      } on ApiException catch (x) {
        if (x.status == 401) rethrow;
        if (x.status == 409) {
          await _conflict(e.item, x.item);
        } else if (x.status == 429 || x.status >= 500) {
          return; // server busy or failing: the outbox waits for the next round
        } else if (mirror.recordOutboxFailure(e.item.id, x.code) >=
            maxAttempts) {
          mirror.rejectOutbox(e.item.id); // 400, 403, 413…
        }
      }
    }
  }

  /// Server accepted [sent]: mirror it; drop the outbox entry unless it was edited meanwhile (then rebase it).
  void _settle(Item sent, Item stored) {
    mirror.upsertItems([stored]);
    final queued = mirror
        .outbox()
        .where((o) => o.item.id == sent.id)
        .firstOrNull;
    if (queued == null) return;
    if (jsonEncode(queued.item.toJson()) == jsonEncode(sent.toJson())) {
      mirror.removeOutbox(sent.id);
    } else {
      mirror.rebaseOutbox(sent.id, stored.revision!);
    }
  }

  Future<void> _conflict(Item mine, Item? current) async {
    if (current == null) {
      return mirror.rebaseOutbox(
        mine.id,
        0,
      ); // gone without a tombstone: create again
    }
    final ours =
        current.updatedDevice == deviceId &&
        current.deleted == mine.deleted &&
        jsonEncode(current.meta?.toJson()) == jsonEncode(mine.meta?.toJson());
    if (ours) return _settle(mine, current); // our write, its response was lost
    mirror.upsertItems([current]);
    if (mine.kind == ItemKind.knownHost) {
      return mirror.removeOutbox(
        mine.id,
      ); // server copy kept; the ledger's hostPins decide here
    }
    final deletedThere = current.purged || (current.deleted && !mine.deleted);
    if (!deletedThere && (mine.deleted || mine.kind == ItemKind.profile)) {
      return mirror.rebaseOutbox(
        mine.id,
        current.revision!,
      ); // our delete (restorable) or the profile (last write wins)
    }
    final copy = mine.deleted
        ? null
        : await copyOf?.call(
            mine,
            personal: false,
          ); // deletion wins; the server version wins
    mirror.removeOutbox(mine.id);
    if (copy != null) mirror.enqueue(copy, baseRevision: 0);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
