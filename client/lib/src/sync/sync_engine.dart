// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../storage/local_mirror.dart';
import '../version.dart';

/// The ApiInfo the last sync round stored in [mirror].
ApiInfo? storedApiInfo(LocalMirror mirror) =>
    switch (mirror.getKv(KvKey.apiInfo)) {
      final raw? => ApiInfo.fromJson(jsonDecode(raw)),
      null => null,
    };

/// Push the outbox, pull the server's changes: at start, after each local change, every [interval].
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.api,
    required this.mirror,
    required this.deviceId,
    this._now = DateTime.now,
  }) {
    api.isReadOnly = () =>
        compat?.mode == CompatMode.readOnly ||
        (mirror.getKv(KvKey.refusedEpoch) != null && !_apiIgnoresRefusal);
  }

  final ApiClient api;
  final LocalMirror mirror;
  final String deviceId;
  static const interval = Duration(seconds: 30);
  final DateTime Function() _now;

  static const maxAttempts = 3;
  static const maxBackoff = Duration(minutes: 10);

  /// Conflict copy of a local write (the vault seals it).
  Future<Item?> Function(Item mine, {required bool personal})? copyOf;

  /// The local view must be rebuilt (the vault reloads).
  Future<void> Function()? onChanged;
  void Function(UnauthorizedReason? reason)? onUnauthorized;

  /// An accepted server restore: the ledger empties its replay marks (pins stay).
  Future<void> Function()? onRestoreAccepted;

  /// Called with each block that arrives, after its pages and the itemIds rule are applied.
  Future<void> Function(OrgBlock block)? onOrgBlock;
  bool _resyncing = false;

  bool online = true;
  Object? lastError;
  DateTime? lastSyncAt;
  Compat? compat;

  /// A newer client's version: only its text is shown, the link is compiled in.
  String? updateVersion;

  bool get readOnly => compat?.mode == CompatMode.readOnly || restoreRefused;

  /// Writes the server refused 3 times; they wait for retry, keep a personal copy, or discard.
  List<OutboxEntry> get rejected => [
    for (final e in mirror.outbox())
      if (e.state == OutboxState.rejected) e,
  ];

  /// The ids of [rejected], without opening the outbox rows.
  List<String> get rejectedIds => mirror.outboxIds(state: OutboxState.rejected);

  /// The ApiInfo the last successful round stored, parsed once per round.
  ApiInfo? get storedInfo => _storedInfo ??= storedApiInfo(mirror);
  ApiInfo? _storedInfo;

  Timer? _timer;

  // The mirror changed during this round: the vault reloads at its end.
  bool _changed = false;
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
    if (readOnly) throw const ReadOnlyException();
    mirror.enqueue(item, baseRevision: item.revision ?? 0);
    unawaited(syncNow());
  }

  Future<void> retry(String itemId) {
    trace(TraceArea.sync, 'retry ${shortId(itemId)}');
    mirror.retryOutbox(itemId);
    return syncNow();
  }

  /// The server row is already the shown version: only the local edit goes.
  Future<void> discard(String itemId) async {
    trace(TraceArea.sync, 'discard local edit ${shortId(itemId)}');
    mirror.removeOutbox(itemId);
    await onChanged?.call();
    notifyListeners();
  }

  Future<void> keepPersonalCopy(String itemId) async {
    trace(TraceArea.sync, 'keep a personal copy of ${shortId(itemId)}');
    final entry = mirror.outbox().firstWhere((e) => e.item.id == itemId);
    final copy = await copyOf?.call(entry.item, personal: true);
    mirror.removeOutbox(itemId);
    if (copy != null) mirror.enqueue(copy, baseRevision: 0);
    _changed = true;
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

  Future<void> _round({bool restoring = false}) async {
    trace(TraceArea.sync, restoring ? 'round (restore)' : 'round');
    try {
      final info = await api.info();
      online = true;
      if (!_negotiate(info)) {
        trace(TraceArea.sync, 'no common API: nothing pushed or pulled');
        return;
      }
      trace(
        TraceArea.sync,
        'compat ${compat!.mode.name}${compat!.reason == null ? '' : ' (${compat!.reason})'}',
      );
      if (!restoring && _mustPause(info)) {
        trace(TraceArea.sync, 'paused: server restored or restore refused');
        return;
      }
      if (restoring) await _pull(full: true, acceptOlder: true);
      // A client too old to write (read-only mode) only pulls.
      if (compat!.mode == CompatMode.full) {
        await _push();
      }
      if (!restoring) await _pull();
      // A missing epoch never replaces the stored one.
      final stored = _storedEpoch;
      final raw = jsonEncode({
        ...info.toJson(),
        if (info.instanceEpoch == null && stored != null)
          'instanceEpoch': stored,
      });
      mirror.setKv(KvKey.apiInfo, raw);
      _storedInfo = ApiInfo.fromJson(jsonDecode(raw));
      if (restoring) _finishRestore();
      lastSyncAt = _now();
      lastError = null;
      trace(TraceArea.sync, 'round done, outbox ${mirror.outboxIds().length}');
    } on NetworkException catch (e) {
      trace(TraceArea.sync, 'offline');
      online = false;
      lastError = e;
    } on ApiException catch (e) {
      trace(
        TraceArea.sync,
        'server said ${e.status} ${e.code}${e.reason == null ? '' : '/${e.reason}'}',
      );
      if (e.status == 401) {
        onUnauthorized?.call(e.unauthorizedReason);
      } else if (e.conflictReason == ConflictReason.cursorAhead) {
        _pending = true;
      } else {
        lastError = e;
      }
    } on FormatException catch (e) {
      trace(TraceArea.sync, 'unreadable server answer');
      // A protocol error shows in the sync banner and is retried next round; nothing is deleted.
      lastError = e;
    } on ReadOnlyException catch (e) {
      trace(TraceArea.sync, 'read-only switched on during the round');
      // Nothing is lost: the outbox stays for a later round.
      lastError = e;
    } finally {
      if (_changed) {
        _changed = false;
        await onChanged?.call();
      }
      notifyListeners();
    }
  }

  // False when there is no common API: no push, no pull.
  bool _negotiate(ApiInfo info) {
    compat = negotiate(clientVersion, clientApis, info);
    updateVersion = compareVersions(info.latestClient, clientVersion) > 0
        ? info.latestClient
        : null;
    _apiIgnoresRefusal = _accepting;
    return compat!.api != null;
  }

  // A write answered 409 `client_too_old` although the info said compatible: read-only, stop pushing.
  void _tooOld() {
    compat = Compat(CompatMode.readOnly, compat?.api, 'client-too-old');
  }

  Future<void> _pull({bool full = false, bool acceptOlder = false}) async {
    var cursor = full ? 0 : int.parse(mirror.getKv(KvKey.cursor) ?? '0');
    var orgCursor = full ? 0 : int.parse(mirror.getKv(KvKey.orgCursor) ?? '0');
    final seen = <String>{};
    OrgBlock? arrived;
    // Ids received after the block's response: their seq is above its cursor.
    final later = <String>{};
    for (var more = true; more;) {
      // The page is parsed whole before anything is applied.
      final page = await api.sync(cursor: cursor, orgCursor: orgCursor);
      mirror.upsertItems(page.items, acceptOlder: acceptOlder);
      if (page.items.isNotEmpty) _changed = true;
      seen.addAll(page.items.map((i) => i.id));
      if (arrived != null) later.addAll(page.items.map((i) => i.id));
      if (page.org case final org?) {
        mirror
          ..setKv(KvKey.orgBlock, jsonEncode(org.toJson()))
          ..setKv(KvKey.orgCursor, '${org.orgCursor}');
        orgCursor = org.orgCursor;
        arrived = org;
        _changed = true;
        later.clear();
      }
      trace(
        TraceArea.sync,
        'pulled ${page.items.length} items, cursor $cursor → ${page.cursor}',
      );
      cursor = page.cursor;
      mirror.setKv(KvKey.cursor, '$cursor');
      more = page.more;
    }
    if (full) {
      // Replaced by the server's, only once the whole pull succeeded; queued items stay.
      final queued = mirror.outboxIds().toSet();
      _delete([
        for (final id in mirror.itemIds())
          if (!seen.contains(id) && !queued.contains(id)) id,
      ]);
    }
    if (arrived == null) return;
    final visible = arrived.itemIds.toSet();
    final queued = mirror.outboxIds().toSet();
    _delete([
      for (final id in mirror.itemIds(scope: ItemScope.org))
        if (!visible.contains(id) &&
            !queued.contains(id) &&
            !later.contains(id))
          id,
    ]);
    final held = mirror.itemIds();
    if (!full && !_resyncing && visible.any((id) => !held.contains(id))) {
      // Only once: a server that keeps listing a missing id cannot loop us.
      _resyncing = true;
      try {
        return await _pull(full: true, acceptOlder: acceptOlder);
      } finally {
        _resyncing = false;
      }
    }
    await onOrgBlock?.call(arrived);
  }

  void _delete(List<String> ids) {
    if (ids.isEmpty) return;
    mirror.deleteItems(ids);
    _changed = true;
  }

  // The epoch of the last /api/info, for a refusal.
  String? _seenEpoch;
  bool _pending = false;
  // The accepted round may write although the refusal is still stored.
  bool _accepting = false;

  // The API applies a stored refusal from the first negotiation on, except in a negotiation of an accepted restore.
  bool _apiIgnoresRefusal = true;

  bool get restoreRefused =>
      !_accepting && mirror.getKv(KvKey.refusedEpoch) != null;
  bool get restorePending => _pending || restoreRefused;

  String? get _storedEpoch => storedInfo?.instanceEpoch;

  // Called after negotiation on every normal round. No push, no pull while it returns true.
  bool _mustPause(ApiInfo info) {
    _seenEpoch = info.instanceEpoch;
    final stored = _storedEpoch;
    final changed =
        info.instanceEpoch == null ||
        (stored != null && info.instanceEpoch != stored);
    if (changed || restoreRefused) _pending = true;
    return _pending;
  }

  Future<void> refuseRestore() async {
    trace(TraceArea.sync, 'restore refused: read-only');
    // An empty string marks a missing epoch.
    mirror.setKv(KvKey.refusedEpoch, _seenEpoch ?? _storedEpoch ?? '');
    _apiIgnoresRefusal = false;
    notifyListeners();
  }

  Future<void> acceptRestore() async {
    trace(TraceArea.sync, 'restore accepted: full pull');
    // Resets cursor, orgCursor and orgBlock, and empties the anchors.
    mirror.resetForRestore();
    // LedgerStore.reset: marks emptied, pins kept.
    await onRestoreAccepted?.call();
    _pending = false;
    _accepting = true;
    try {
      // A full pull that accepts older revisions, a push, then the ApiInfo is stored.
      await _single(() => _round(restoring: true));
    } finally {
      _accepting = false;
      _apiIgnoresRefusal = false;
    }
  }

  void _finishRestore() {
    mirror.setKv(KvKey.refusedEpoch, null);
  }

  Future<void> _push() async {
    if (_pushAfter case final after? when _now().isBefore(after)) return;
    for (final e in mirror.outbox().where(
      (e) => e.state == OutboxState.pending,
    )) {
      try {
        _settle(e.item, await api.putItem(e.item, ifMatch: e.baseRevision));
        trace(
          TraceArea.sync,
          'pushed ${e.item.kind.name} ${shortId(e.item.id)}',
        );
        _failures = 0;
        _pushAfter = null;
      } on NetworkException {
        // Nothing is counted on the entry; the round then marks the client offline.
        _backOff(null);
        rethrow;
      } on ApiException catch (x) {
        if (x.status == 401) rethrow;
        trace(
          TraceArea.sync,
          'push ${shortId(e.item.id)} refused: ${x.status} ${x.reason ?? x.code}',
        );
        if (x.conflictReason == ConflictReason.clientTooOld) {
          return _tooOld();
        }
        if (x.status == 409) {
          await _conflict(e.item, x.item);
        } else if (x.status == 429 || x.status >= 500) {
          // Nothing is counted on the entry.
          return _backOff(x.retryAfter);
        } else if (mirror.recordOutboxFailure(e.item.id, x.code) >=
            maxAttempts) {
          // Other refusals (400, 403, 413 and the like) reject the entry after maxAttempts.
          mirror.rejectOutbox(e.item.id);
          _changed = true;
        }
      }
    }
  }

  // interval * 2^(failures - 1), capped at maxBackoff; a longer `retry-after` wins.
  void _backOff(Duration? retryAfter) {
    _failures++;
    final doubled = interval * (1 << (_failures - 1).clamp(0, 20));
    var wait = doubled < maxBackoff ? doubled : maxBackoff;
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    _pushAfter = _now().add(wait);
    trace(TraceArea.sync, 'push backs off ${wait.inSeconds} s');
  }

  // The server accepted sent: mirror it; drop the outbox entry unless it was edited meanwhile (then rebase it).
  void _settle(Item sent, Item stored) {
    mirror.upsertItems([stored]);
    _changed = true;
    final queued = mirror.outboxEntry(sent.id);
    if (queued == null) return;
    if (jsonEncode(queued.item.toJson()) == jsonEncode(sent.toJson())) {
      mirror.removeOutbox(sent.id);
    } else {
      mirror.rebaseOutbox(sent.id, stored.revision!);
    }
  }

  Future<void> _conflict(Item mine, Item? current) async {
    _changed = true;
    // Gone without a tombstone: create it again.
    if (current == null) {
      return mirror.rebaseOutbox(mine.id, 0);
    }
    final ours =
        current.updatedDevice == deviceId &&
        current.deleted == mine.deleted &&
        jsonEncode(current.meta?.toJson()) == jsonEncode(mine.meta?.toJson());
    // Our own write, whose response was lost.
    if (ours) return _settle(mine, current);
    trace(TraceArea.sync, 'conflict on ${mine.kind.name} ${shortId(mine.id)}');
    mirror.upsertItems([current]);
    // The server copy of a known host is kept; the ledger's hostPins decide here.
    if (mine.kind == ItemKind.knownHost) {
      return mirror.removeOutbox(mine.id);
    }
    final deletedThere = current.purged || (current.deleted && !mine.deleted);
    // Our delete (restorable) or the profile (last write wins) goes over the server's.
    if (!deletedThere && (mine.deleted || mine.kind == ItemKind.profile)) {
      return mirror.rebaseOutbox(mine.id, current.revision!);
    }
    // Otherwise the server's deletion or version wins; an edit of ours is kept as a copy.
    final copy = mine.deleted
        ? null
        : await copyOf?.call(mine, personal: false);
    mirror.removeOutbox(mine.id);
    if (copy != null) mirror.enqueue(copy, baseRevision: 0);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
