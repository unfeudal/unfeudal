// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../storage/local_mirror.dart';
import '../version.dart';

/// Push the outbox, pull the server's changes: at start, after each local change, every [interval].
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.api,
    required this.mirror,
    required this.deviceId,
    this._now = DateTime.now,
  });

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
  void Function(String? reason)? onUnauthorized;

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
      if (compat!.mode == CompatMode.full) {
        await _push(); // client-too-old: pull only
      }
      if (!restoring) await _pull();
      final stored =
          _storedEpoch; // a missing epoch never replaces the stored one
      mirror.setKv(
        KvKey.apiInfo,
        jsonEncode({
          ...info.toJson(),
          if (info.instanceEpoch == null && stored != null)
            'instanceEpoch': stored,
        }),
      );
      if (restoring) _finishRestore();
      lastSyncAt = _now();
      lastError = null;
      trace(TraceArea.sync, 'round done, outbox ${mirror.outbox().length}');
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
        onUnauthorized?.call(e.reason);
      } else if (e.reason == 'cursor_ahead') {
        _pause();
      } else {
        lastError = e;
      }
    } on FormatException catch (e) {
      trace(TraceArea.sync, 'unreadable server answer');
      lastError = e; // protocol error: shown in the sync banner, retried next round; nothing deleted
    } on ReadOnlyException catch (e) {
      trace(TraceArea.sync, 'read-only switched on during the round');
      lastError = e; // read-only switched on during the round; nothing lost, the outbox stays
    } finally {
      await onChanged?.call();
      notifyListeners();
    }
  }

  /// False when there is no common API: no push, no pull.
  bool _negotiate(ApiInfo info) {
    compat = negotiate(clientVersion, clientApis, info);
    updateVersion = compareVersions(info.latestClient, clientVersion) > 0
        ? info.latestClient
        : null;
    api.readOnly = readOnly;
    return compat!.api != null;
  }

  /// A write answered 409 `client_too_old` although the info said compatible: read-only, stop pushing.
  void _tooOld() {
    compat = Compat(CompatMode.readOnly, compat?.api, 'client-too-old');
    api.readOnly = true;
  }

  Future<void> _pull({bool full = false, bool acceptOlder = false}) async {
    var cursor = full ? 0 : int.parse(mirror.getKv(KvKey.cursor) ?? '0');
    var orgCursor = full ? 0 : int.parse(mirror.getKv(KvKey.orgCursor) ?? '0');
    final seen = <String>{};
    OrgBlock? arrived;
    final later = <String>{}; // ids received after the block's response: their seq is above its cursor
    for (var more = true; more;) {
      final page = await api.sync(
        cursor: cursor,
        orgCursor: orgCursor,
      ); // parsed whole before anything is applied
      mirror.upsertItems(page.items, acceptOlder: acceptOlder);
      seen.addAll(page.items.map((i) => i.id));
      if (arrived != null) later.addAll(page.items.map((i) => i.id));
      if (page.org case final org?) {
        mirror
          ..setKv(KvKey.orgBlock, jsonEncode(org.toJson()))
          ..setKv(KvKey.orgCursor, '${org.orgCursor}');
        orgCursor = org.orgCursor;
        arrived = org;
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
      final queued = {for (final e in mirror.outbox()) e.item.id};
      mirror.deleteItems([
        for (final i in mirror.items())
          if (!seen.contains(i.id) && !queued.contains(i.id)) i.id,
      ]);
    }
    if (arrived == null) return;
    final visible = arrived.itemIds.toSet();
    final queued = {for (final e in mirror.outbox()) e.item.id};
    mirror.deleteItems([
      for (final i in mirror.items())
        if (i.scope == ItemScope.org &&
            !visible.contains(i.id) &&
            !queued.contains(i.id) &&
            !later.contains(i.id))
          i.id,
    ]);
    final held = {for (final i in mirror.items()) i.id};
    if (!full && !_resyncing && visible.any((id) => !held.contains(id))) {
      _resyncing =
          true; // once: a server that keeps listing a missing id cannot loop us
      try {
        return await _pull(full: true, acceptOlder: acceptOlder);
      } finally {
        _resyncing = false;
      }
    }
    await onOrgBlock?.call(arrived);
  }

  String? _seenEpoch; // epoch of the last /api/info, for a refusal
  bool _pending = false;
  bool _accepting = false; // the accepted round may write although the refusal is still stored

  bool get restoreRefused =>
      !_accepting && mirror.getKv(KvKey.refusedEpoch) != null;
  bool get restorePending => _pending || restoreRefused;

  String? get _storedEpoch {
    final raw = mirror.getKv(KvKey.apiInfo);
    return raw == null ? null : ApiInfo.fromJson(jsonDecode(raw)).instanceEpoch;
  }

  /// Called after negotiation on every normal round. No push, no pull while it returns true.
  bool _mustPause(ApiInfo info) {
    _seenEpoch = info.instanceEpoch;
    final stored = _storedEpoch;
    final changed =
        info.instanceEpoch == null ||
        (stored != null && info.instanceEpoch != stored);
    if (changed || restoreRefused) _pending = true;
    return _pending;
  }

  void _pause() => _pending = true; // 409 cursor_ahead

  Future<void> refuseRestore() async {
    trace(TraceArea.sync, 'restore refused: read-only');
    mirror.setKv(
      KvKey.refusedEpoch,
      _seenEpoch ?? _storedEpoch ?? '',
    ); // '' marks a missing epoch
    api.readOnly = true;
    notifyListeners();
  }

  Future<void> acceptRestore() async {
    trace(TraceArea.sync, 'restore accepted: full pull');
    mirror.resetForRestore(); // cursor, orgCursor, orgBlock reset; anchors emptied
    await onRestoreAccepted
        ?.call(); // LedgerStore.reset: marks emptied, pins kept
    _pending = false;
    _accepting = true;
    try {
      await _single(
        () => _round(restoring: true),
      ); // full pull (acceptOlder), push, then store ApiInfo
    } finally {
      _accepting = false;
      api.readOnly = readOnly;
    }
  }

  void _finishRestore() {
    mirror.setKv(KvKey.refusedEpoch, null);
    api.readOnly = readOnly;
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
        _backOff(null); // nothing counted on the entry; the round then marks the client offline
        rethrow;
      } on ApiException catch (x) {
        if (x.status == 401) rethrow;
        trace(
          TraceArea.sync,
          'push ${shortId(e.item.id)} refused: ${x.status} ${x.reason ?? x.code}',
        );
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
    trace(TraceArea.sync, 'push backs off ${wait.inSeconds} s');
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
    trace(TraceArea.sync, 'conflict on ${mine.kind.name} ${shortId(mine.id)}');
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
