// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../storage/local_mirror.dart';
import '../version.dart';
import 'conflict_resolver.dart';
import 'item_puller.dart';
import 'outbox_pusher.dart';
import 'restore_gate.dart';

/// The ApiInfo the last sync round stored in [mirror].
ApiInfo? storedApiInfo(LocalMirror mirror) =>
    switch (mirror.kv(KvKey.apiInfo)) {
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
        compat?.mode == CompatMode.readOnly || _restore.apiRefusesWrites;
  }

  static const interval = Duration(seconds: 30);
  static const maxAttempts = 3;
  static const maxBackoff = Duration(minutes: 10);

  final ApiClient api;
  final LocalMirror mirror;
  final String deviceId;
  final DateTime Function() _now;

  /// Conflict copy of a local write (the vault seals it).
  Future<Item?> Function(Item mine, {required bool personal})? copyOf;

  /// The local view must be rebuilt (the vault reloads).
  Future<void> Function()? onChanged;
  void Function(UnauthorizedReason? reason)? onUnauthorized;

  /// An accepted server restore: the ledger empties its replay marks (pins stay).
  Future<void> Function()? onRestoreAccepted;

  /// Called with each block that arrives, after its pages and the itemIds rule are applied.
  Future<void> Function(OrgBlock block)? onOrgBlock;

  bool isOnline = true;
  Object? lastError;
  DateTime? lastSyncAt;
  Compat? compat;

  /// A newer client's version: only its text is shown, the link is compiled in.
  String? updateVersion;

  late final _restore = RestoreGate(mirror);
  late final _resolver = ConflictResolver(
    mirror: mirror,
    deviceId: deviceId,
    markChanged: _markChanged,
    // The hooks are read on each call: they are assigned after construction.
    copyOf: (mine, {required personal}) async =>
        copyOf?.call(mine, personal: personal),
  );
  late final _pusher = OutboxPusher(
    api: api,
    mirror: mirror,
    resolver: _resolver,
    markChanged: _markChanged,
    onClientTooOld: _tooOld,
    now: _now,
    interval: interval,
    maxAttempts: maxAttempts,
    maxBackoff: maxBackoff,
  );
  late final _puller = ItemPuller(
    api: api,
    mirror: mirror,
    markChanged: _markChanged,
    onOrgBlock: (block) async => onOrgBlock?.call(block),
  );

  ApiInfo? _storedInfo;
  Timer? _timer;
  // The mirror changed during this round: the vault reloads at its end.
  bool _changed = false;
  Future<void>? _running;
  bool _again = false;

  // A round still in flight when the engine is disposed ends without notifying.
  bool _disposed = false;

  bool get isReadOnly =>
      compat?.mode == CompatMode.readOnly || isRestoreRefused;

  bool get isRestoreRefused => _restore.isRestoreRefused;
  bool get isRestorePending => _restore.isRestorePending;

  /// Online with no round finished, failed or paused yet: a first sync is still bringing the items.
  bool get isFirstSyncPending =>
      isOnline &&
      lastSyncAt == null &&
      lastError == null &&
      !isRestorePending &&
      (compat == null || compat!.api != null);

  /// Writes the server refused [maxAttempts] times; they wait for retry, keep a personal copy, or discard.
  List<OutboxEntry> get rejected => [
    for (final e in mirror.outbox())
      if (e.state == OutboxState.rejected) e,
  ];

  /// The ids of [rejected], without opening the outbox rows.
  List<String> get rejectedIds => mirror.outboxIds(state: OutboxState.rejected);

  /// The ApiInfo the last successful round stored, parsed once per round.
  ApiInfo? get storedInfo => _storedInfo ??= storedApiInfo(mirror);

  String? get _storedEpoch => storedInfo?.instanceEpoch;

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

  Future<void> write(Item item) => writeAll([item]);

  /// Queues every item at once, then one round pushes them.
  Future<void> writeAll(List<Item> items) async {
    if (isReadOnly) throw const ReadOnlyException();
    mirror.enqueueAll(items);
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

  Future<void> refuseRestore() async {
    trace(TraceArea.sync, 'restore refused: read-only');
    _restore.refuse(storedEpoch: _storedEpoch);
    notifyListeners();
  }

  Future<void> acceptRestore() async {
    trace(TraceArea.sync, 'restore accepted: full pull');
    // Resets cursor, orgCursor and orgBlock, and empties the anchors.
    mirror.resetForRestore();
    // LedgerStore.reset: marks emptied, pins kept.
    await onRestoreAccepted?.call();
    // A full pull that accepts older revisions, a push, then the ApiInfo is stored.
    await _restore.accept(() => _single(() => _round(restoring: true)));
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
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
      isOnline = true;
      if (!_negotiate(info)) {
        trace(TraceArea.sync, 'no common API: nothing pushed or pulled');
        return;
      }
      trace(
        TraceArea.sync,
        'compat ${compat!.mode.name}${compat!.reason == null ? '' : ' (${compat!.reason!.name})'}',
      );
      if (!restoring && _restore.mustPause(info, storedEpoch: _storedEpoch)) {
        trace(TraceArea.sync, 'paused: server restored or restore refused');
        return;
      }
      if (restoring) await _puller.pull(PullMode.restore);
      // A client too old to write (read-only mode) only pulls.
      if (compat!.mode == CompatMode.full) {
        await _pusher.push();
      }
      if (!restoring) await _puller.pull();
      _storeInfo(info);
      if (restoring) _restore.finish();
      lastSyncAt = _now();
      lastError = null;
      trace(TraceArea.sync, 'round done, outbox ${mirror.outboxIds().length}');
    } on NetworkException catch (e) {
      trace(TraceArea.sync, 'offline');
      isOnline = false;
      lastError = e;
    } on ApiException catch (e) {
      trace(
        TraceArea.sync,
        'server said ${e.status} ${e.code}${e.reason == null ? '' : '/${e.reason}'}',
      );
      if (e.status == 401) {
        onUnauthorized?.call(e.unauthorizedReason);
      } else if (e.conflictReason == ConflictReason.cursorAhead) {
        _restore.markPending();
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
    } on Object catch (e) {
      // The round runs from a timer, where a thrown error would be lost: it shows in the
      // sync banner instead, the outbox stays and the next round retries.
      trace(TraceArea.sync, 'round failed: ${e.runtimeType}');
      lastError = e;
    } finally {
      await _reloadIfChanged();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _reloadIfChanged() async {
    if (!_changed) return;
    _changed = false;
    try {
      await onChanged?.call();
    } on Object catch (e) {
      // A failed reload must not stop the listeners from hearing about the round.
      trace(TraceArea.sync, 'reload failed: ${e.runtimeType}');
      lastError = e;
    }
  }

  // False when there is no common API: no push, no pull.
  bool _negotiate(ApiInfo info) {
    compat = negotiate(clientVersion, clientApis, info);
    updateVersion = compareVersions(info.latestClient, clientVersion) > 0
        ? info.latestClient
        : null;
    _restore.onNegotiated();
    return compat!.api != null;
  }

  // A write answered 409 `client_too_old` although the info said compatible: read-only, stop pushing.
  void _tooOld() {
    compat = Compat(
      CompatMode.readOnly,
      compat?.api,
      CompatReason.clientTooOld,
    );
  }

  void _storeInfo(ApiInfo info) {
    // A missing epoch never replaces the stored one.
    final stored = _storedEpoch;
    final raw = jsonEncode({
      ...info.toJson(),
      if (info.instanceEpoch == null && stored != null) 'instanceEpoch': stored,
    });
    mirror.setKv(KvKey.apiInfo, raw);
    _storedInfo = ApiInfo.fromJson(jsonDecode(raw));
  }

  void _markChanged() => _changed = true;
}
