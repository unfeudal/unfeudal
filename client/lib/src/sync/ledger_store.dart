// SPDX-License-Identifier: Apache-2.0
import 'dart:math';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../storage/local_mirror.dart';
import '../storage/sealed_kv.dart';

/// The sealed per-device ledger in `kv.ledger`: replay marks, host and member pins, startup approvals.
class LedgerStore {
  LedgerStore(LocalMirror mirror)
    : _store = SealedKv(mirror, KvKey.ledger, ledgerAad);

  final SealedKv _store;
  Ledger _ledger = Ledger.empty();
  final _handedOut = <String, int>{};

  /// False when a stored ledger could not be opened: it restarts empty and the caller reports it.
  Future<bool> load(Uint8List userKey) {
    _handedOut.clear();
    _ledger = Ledger.empty();
    return _store.load(userKey, (json) => _ledger = Ledger.fromJson(json));
  }

  int mark(String id, PayloadPart part) => _ledger.seq[_seqKey(id, part)] ?? 0;

  /// Marks rise only, from confirmed payloads.
  void confirm(String id, PayloadPart part, int seq) {
    if (seq > mark(id, part)) _ledger.seq[_seqKey(id, part)] = seq;
  }

  /// A missing `_seq` counts as 0: once a mark exists, it is a replay.
  bool isReplay(String id, PayloadPart part, int? seq) =>
      (seq ?? 0) < mark(id, part);

  /// Above both marks and every seq handed out this session for [id].
  int nextSeq(String id) {
    final next =
        [
          mark(id, PayloadPart.meta),
          mark(id, PayloadPart.secret),
          _handedOut[id] ?? 0,
        ].reduce(max) +
        1;
    _handedOut[id] = next;
    return next;
  }

  KnownHostMeta? hostPin(String hostId) => _ledger.hostPins[hostId];

  Future<void> setHostPin(String hostId, KnownHostMeta pin) {
    _ledger.hostPins[hostId] = pin;
    return save();
  }

  ({String fingerprint, bool verified})? memberPin(String userId) =>
      _ledger.memberPins[userId];

  Future<void> setMemberPin(
    String userId,
    ({String fingerprint, bool verified}) pin,
  ) {
    _ledger.memberPins[userId] = pin;
    return save();
  }

  /// SHA-256 (base64) of the startup command approved for [hostId].
  String? startupApproval(String hostId) => _ledger.startupApprovals[hostId];

  Future<void> approveStartup(String hostId, String hash) {
    _ledger.startupApprovals[hostId] = hash;
    return save();
  }

  Future<void> save() => _store.save(_ledger.toJson());

  /// Accepted server restore: replay marks go, pins and approvals stay.
  Future<void> reset() {
    _ledger = Ledger(
      seq: {},
      hostPins: _ledger.hostPins,
      memberPins: _ledger.memberPins,
      startupApprovals: _ledger.startupApprovals,
      extra: _ledger.extra,
    );
    _handedOut.clear();
    return save();
  }

  /// On lock: forgets the key and everything held in memory.
  void close() {
    _store.close();
    _ledger = Ledger.empty();
    _handedOut.clear();
  }

  static String _seqKey(String id, PayloadPart part) => '$id/${part.name}';
}
