// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/loquet/mood.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  test('cheerful with nothing pending, idle with pending work, concerned past the thresholds', () {
    expect(computeMood(VaultHealth.none), LoquetMood.cheerful);
    expect(computeMood(const VaultHealth(hostsToVerify: 1)), LoquetMood.idle);
    expect(computeMood(const VaultHealth(conflicts: 1)), LoquetMood.concerned);
    expect(
      computeMood(const VaultHealth(hostsToVerify: 2, verifyOver7Days: 1)),
      LoquetMood.concerned,
    );
    expect(
      computeMood(const VaultHealth(keysOver5Years: 1)),
      LoquetMood.concerned,
    );
    expect(
      computeMood(const VaultHealth(syncOver7Days: true)),
      LoquetMood.concerned,
    );
  });

  test('reasons in a fixed order', () {
    const h = VaultHealth(
      verifyOver7Days: 2,
      conflicts: 1,
      keysOver5Years: 3,
      syncOver7Days: true,
    );
    expect(h.reasons, [
      MoodReason.verify,
      MoodReason.conflicts,
      MoodReason.oldKeys,
      MoodReason.staleSync,
    ]);
  });

  test('vaultHealthOf reads hosts, keys, conflict names, rejected writes and the last sync; ages count from createdAt', () async {
    final key = SymmetricCipher.newKey();
    final mirror = LocalMirror.inMemory()
      ..upsertItems([
        await sealItem(
          key,
          meta: hostJson('web'),
          createdAt: DateTime.utc(2026, 10, 1),
        ), // updated 2026-10-14, no pin
        await sealItem(key, meta: hostJson('db (conflict copy)')),
        await sealItem(
          key,
          type: 'identity',
          createdAt: DateTime.utc(2021, 10, 1),
          meta: {
            'schemaVersion': 1,
            'name': 'deploy',
            'kind': 'privateKey',
            'publicKey': 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl',
          },
        ),
      ]);
    final v = await testVault(key, mirror);
    final early = vaultHealthOf(
      v,
      now: DateTime.utc(2026, 10, 15),
      lastSyncAt: DateTime.utc(2026, 10, 15),
      rejected: 0,
      conflictSuffixes: {' (conflict copy)', ' (copie en conflit)'},
    );
    expect(
      (
        early.hostsToVerify,
        early.verifyOver7Days,
        early.conflicts,
        early.keysOver5Years,
        early.syncOver7Days,
      ),
      (2, 1, 1, 1, false),
    );
    final late = vaultHealthOf(
      v,
      now: DateTime.utc(2031, 11, 1),
      lastSyncAt: null,
      rejected: 2,
      conflictSuffixes: {' (conflict copy)'},
    );
    expect(
      (
        late.verifyOver7Days,
        late.conflicts,
        late.keysOver5Years,
        late.syncOver7Days,
      ),
      (2, 3, 1, true),
    );
  });
}
