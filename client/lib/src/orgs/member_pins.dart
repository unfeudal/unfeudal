// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../vault/vault.dart';

enum PinCheck { unpinned, matches, changed }

/// Members' public keys this user accepted: the ledger wins, the synced `memberPin` items carry them to other devices.
class MemberPins {
  MemberPins(this.vault);
  final Vault vault;

  ({String fingerprint, bool verified})? pinOf(String userId) {
    if (vault.ledger.memberPin(userId) case final pin?) return pin;
    final meta = _entryOf(userId)?.$2;
    return meta == null
        ? null
        : (fingerprint: meta.fingerprint, verified: meta.verified);
  }

  PinCheck check(String userId, List<int> publicKey) => switch (pinOf(userId)) {
    null => PinCheck.unpinned,
    final pin =>
      pin.fingerprint == keyFingerprint(publicKey)
          ? PinCheck.matches
          : PinCheck.changed,
  };

  /// Ledger first, then the synced item.
  Future<void> pin(
    String userId,
    List<int> publicKey, {
    required bool verified,
  }) async {
    final fingerprint = keyFingerprint(publicKey);
    await vault.ledger.setMemberPin(userId, (
      fingerprint: fingerprint,
      verified: verified,
    ));
    await vault.upsertItem(
      type: 'memberPin',
      id: _entryOf(userId)?.$1.id,
      meta: MemberPinMeta(
        userId: userId,
        fingerprint: fingerprint,
        verified: verified,
      ).toJson(),
    );
  }

  /// Copies a synced pin into the ledger only for a user the ledger has none for.
  void seed() {
    for (final e in vault.ofKind(ItemKind.memberPin)) {
      if (e.state != EntryState.ok || e.orgId != null) continue;
      final meta = MemberPinMeta.fromJson(e.meta);
      if (vault.ledger.memberPin(meta.userId) == null) {
        unawaited(
          vault.ledger.setMemberPin(meta.userId, (
            fingerprint: meta.fingerprint,
            verified: meta.verified,
          )),
        );
      }
    }
  }

  /// The `ok` memberPin entry of [userId] with the smallest id.
  (VaultEntry, MemberPinMeta)? _entryOf(String userId) {
    final e = Vault.winner(
      vault.ofKind(ItemKind.memberPin),
      (e) => MemberPinMeta.fromJson(e.meta).userId == userId,
    );
    return e == null ? null : (e, MemberPinMeta.fromJson(e.meta));
  }
}
