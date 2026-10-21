// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';

import '../events/app_events.dart';
import '../storage/local_mirror.dart';
import '../vault/vault.dart';
import 'sync_engine.dart';

/// What the screens hear of the sync engine and the vault. Going online or offline is an event once per
/// change; a round that changes nothing they show, and leaves the vault as it was, notifies nobody.
class SyncWatch {
  SyncWatch({
    required this._emit,
    required this._notify,
    required this._onRound,
    required this._onEntries,
  });

  final void Function(AppEvent) _emit;
  final VoidCallback _notify;
  // After every round, before the screens are told.
  final VoidCallback _onRound;
  // After every change of the vault's entries.
  final VoidCallback _onEntries;

  SyncEngine? _engine;
  Vault? _vault;
  LocalMirror? _mirror;
  bool _wasOnline = true;
  bool _entriesChanged = false;
  Object? _shown;

  /// Follows [engine] and [vault] from now on, in place of the previous ones.
  void watch(SyncEngine engine, Vault vault, LocalMirror mirror) {
    _vault?.removeListener(_vaultChanged);
    _engine = engine..addListener(_roundDone);
    _vault = vault..addListener(_vaultChanged);
    _mirror = mirror;
    _shown = null;
  }

  void _roundDone() {
    final engine = _engine!;
    if (engine.isOnline != _wasOnline) {
      _wasOnline = engine.isOnline;
      _emit(engine.isOnline ? const CameOnline() : const WentOffline());
    }
    _onRound();
    final shown = (
      engine.isOnline,
      engine.lastSyncAt == null,
      '${engine.lastError}',
      engine.compat?.mode,
      engine.compat?.api,
      engine.compat?.reason,
      engine.isReadOnly,
      engine.isRestorePending,
      engine.updateVersion,
      _mirror?.kv(KvKey.apiInfo),
      engine.rejectedIds.join(' '),
    );
    if (!_entriesChanged && shown == _shown) return;
    _entriesChanged = false;
    _shown = shown;
    _notify();
  }

  void _vaultChanged() {
    _entriesChanged = true;
    _onEntries();
  }
}
