// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../vault/vault.dart';
import 'loquet_pose.dart';

enum MoodReason { verify, conflicts, oldKeys, staleSync }

/// The user's own vault, as Loquet's resting mood reads it; never punitive.
class VaultHealth {
  const VaultHealth({
    this.hostsToVerify = 0,
    this.verifyOver7Days = 0,
    this.conflicts = 0,
    this.keysOver5Years = 0,
    this.syncOver7Days = false,
  });

  static const none = VaultHealth();

  final int hostsToVerify;
  final int verifyOver7Days;
  final int conflicts;
  final int keysOver5Years;
  final bool syncOver7Days;

  /// What makes Loquet concerned, in a fixed order.
  List<MoodReason> get reasons => [
    if (verifyOver7Days > 0) MoodReason.verify,
    if (conflicts > 0) MoodReason.conflicts,
    if (keysOver5Years > 0) MoodReason.oldKeys,
    if (syncOver7Days) MoodReason.staleSync,
  ];

  LoquetMood get mood {
    if (reasons.isNotEmpty) return LoquetMood.concerned;
    return hostsToVerify > 0 ? LoquetMood.idle : LoquetMood.cheerful;
  }
}

/// Readable, non-trashed entries only. Ages count from `createdAt`; a pending entry has none and never
/// counts toward an age threshold. [rejected] = outbox writes the server refused.
VaultHealth vaultHealthOf(
  Vault v, {
  required DateTime now,
  required DateTime? lastSyncAt,
  required int rejected,
  required Set<String> conflictSuffixes,
}) {
  bool olderThan(DateTime? t, Duration age) =>
      t != null && now.difference(t) > age;
  var toVerify = 0, verifyOld = 0, conflicts = rejected, oldKeys = 0;
  for (final e in v.entries) {
    if (e.state != EntryState.ok || v.isTrashed(e.id)) continue;
    final name = e.name ?? '';
    if (conflictSuffixes.any(name.endsWith)) conflicts++;
    if (e.kind == ItemKind.host && v.hostKeys.pinOf(e.id) == null) {
      toVerify++;
      if (olderThan(e.item.createdAt, const Duration(days: 7))) verifyOld++;
    }
    if (e.kind == ItemKind.identity &&
        e.meta?['kind'] == IdentityKind.privateKey.name &&
        olderThan(e.item.createdAt, const Duration(days: 5 * 365))) {
      oldKeys++;
    }
  }
  return VaultHealth(
    hostsToVerify: toVerify,
    verifyOver7Days: verifyOld,
    conflicts: conflicts,
    keysOver5Years: oldKeys,
    syncOver7Days:
        lastSyncAt == null || olderThan(lastSyncAt, const Duration(days: 7)),
  );
}
