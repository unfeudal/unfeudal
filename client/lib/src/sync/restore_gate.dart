// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../storage/local_mirror.dart';

/// Whether a server restore pauses sync, was refused (read-only) or is being accepted.
class RestoreGate {
  RestoreGate(this.mirror);

  final LocalMirror mirror;

  // The epoch of the last /api/info, for a refusal.
  String? _seenEpoch;
  bool _pending = false;
  // The accepted round may write although the refusal is still stored.
  bool _accepting = false;
  // The API applies a stored refusal from the first negotiation on, except in a negotiation of an accepted restore.
  bool _apiIgnoresRefusal = true;

  bool get isRestoreRefused =>
      !_accepting && mirror.kv(KvKey.refusedEpoch) != null;
  bool get isRestorePending => _pending || isRestoreRefused;

  /// The API client refuses writes: a refusal is stored and the API applies it.
  bool get apiRefusesWrites =>
      mirror.kv(KvKey.refusedEpoch) != null && !_apiIgnoresRefusal;

  void onNegotiated() => _apiIgnoresRefusal = _accepting;

  /// The server answered `cursor_ahead`: its data is older than ours.
  void markPending() => _pending = true;

  // Called after negotiation on every normal round. No push, no pull while it returns true.
  bool mustPause(ApiInfo info, {required String? storedEpoch}) {
    _seenEpoch = info.instanceEpoch;
    final changed =
        info.instanceEpoch == null ||
        (storedEpoch != null && info.instanceEpoch != storedEpoch);
    if (changed || isRestoreRefused) _pending = true;
    return _pending;
  }

  void refuse({required String? storedEpoch}) {
    // An empty string marks a missing epoch.
    mirror.setKv(KvKey.refusedEpoch, _seenEpoch ?? storedEpoch ?? '');
    _apiIgnoresRefusal = false;
  }

  /// Runs [restoringRound] as the accepted restore, writes allowed despite the stored refusal.
  Future<void> accept(Future<void> Function() restoringRound) async {
    _pending = false;
    _accepting = true;
    try {
      await restoringRound();
    } finally {
      _accepting = false;
      _apiIgnoresRefusal = false;
    }
  }

  /// The accepted restore's round succeeded: the refusal is lifted.
  void finish() => mirror.setKv(KvKey.refusedEpoch, null);
}
