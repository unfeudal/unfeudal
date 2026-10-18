// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../storage/local_mirror.dart';
import '../version.dart';

/// A newer client exists: only its version text is shown, the link is compiled in.
class UpdateNotice {
  const UpdateNotice(this.version);
  final String version;
}

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
  static const maxBackoff = Duration(minutes: 10);

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
  UpdateNotice? updateNotice;

  bool get readOnly => compat?.mode == CompatMode.readOnly;

  /// Writes the server refused 3 times; they wait for retry, keep a personal copy, or discard.
  List<OutboxEntry> get rejected => [
    for (final e in mirror.outbox())
      if (e.state == OutboxState.rejected) e,
  ];

  Timer? _timer;
  int _failures = 0;
  DateTime? _pushAfter;
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

  Future<void> retry(String itemId) {
    mirror.retryOutbox(itemId);
    return syncNow();
  }

  /// The server row is already the shown version: only the local edit goes.
  Future<void> discard(String itemId) async {
    mirror.removeOutbox(itemId);
    await onChanged?.call();
    notifyListeners();
  }

  Future<void> keepPersonalCopy(String itemId) async {
    final entry = mirror.outbox().firstWhere((e) => e.item.id == itemId);
    final copy = await copyOf?.call(entry.item, personal: true);
    mirror.removeOutbox(itemId);
    if (copy != null) mirror.enqueue(copy, baseRevision: 0);
    await syncNow();
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
    updateNotice = compareVersions(info.latestClient, version) > 0
        ? UpdateNotice(info.latestClient)
        : null;
    api.readOnly = readOnly;
    return compat!.api != null;
  }

  /// A write answered 409 `client_too_old` although the info said compatible: read-only, stop pushing.
  void _tooOld() {
    compat = Compat(CompatMode.readOnly, compat?.api, 'client-too-old');
    api.readOnly = true;
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
    if (_pushAfter case final after? when _now().isBefore(after)) return;
    for (final e in mirror.outbox().where(
      (e) => e.state == OutboxState.pending,
    )) {
      try {
        _settle(e.item, await api.putItem(e.item, ifMatch: e.baseRevision));
        _failures = 0;
        _pushAfter = null;
      } on ApiException catch (x) {
        if (x.status == 401) rethrow;
        if (x.status == 409 && x.reason == 'client_too_old') return _tooOld();
        if (x.status == 409) {
          await _conflict(e.item, x.item);
        } else if (x.status == 429 || x.status >= 500) {
          return _backOff(x.retryAfter); // nothing counted on the entry
        } else if (mirror.recordOutboxFailure(e.item.id, x.code) >=
            maxAttempts) {
          mirror.rejectOutbox(e.item.id); // 400, 403, 413…
        }
      }
    }
  }

  /// interval × 2^(failures − 1), capped at [maxBackoff]; a longer `retry-after` wins.
  void _backOff(Duration? retryAfter) {
    _failures++;
    final doubled = interval * (1 << (_failures - 1).clamp(0, 20));
    var wait = doubled < maxBackoff ? doubled : maxBackoff;
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    _pushAfter = _now().add(wait);
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
