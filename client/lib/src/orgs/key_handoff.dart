// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import 'block_permissions.dart';
import 'folder_keyring.dart';
import 'member_pins.dart';

class HandoffReport {
  HandoffReport(this.unconfirmed, this.alerts);
  final Set<String> unconfirmed; // not pinned on this device: the admin confirms them (safety code dialog)
  final Set<String> alerts; // pinned key changed: never sealed to
}

class KeyHandoff {
  KeyHandoff({required this.api, required this.keyring, required this.pins});
  final ApiClient api;
  final FolderKeyring keyring;
  final MemberPins pins;

  Future<HandoffReport> run(OrgBlock block) async {
    final report = HandoffReport({}, {});
    final byFolder = <String, List<WrappedFolderKeys>>{};
    for (final r in block.keyRequests) {
      if (!block.orgs.any((o) => o.id == r.orgId && o.isAdmin)) continue;
      final keys = keyring.current(r.folderId);
      if (keys == null || keys.version != r.version) {
        continue; // not held here: another admin device answers
      }
      final member = block.members
          .where((m) => m.orgId == r.orgId && m.userId == r.userId)
          .firstOrNull;
      final publicKey = member?.publicKey;
      if (publicKey == null || member!.disabled == true) {
        continue; // never a wrap for a disabled member
      }
      switch (pins.check(r.userId, publicKey)) {
        case PinCheck.changed:
          report.alerts.add(r.userId);
          continue;
        case PinCheck.unpinned:
          report.unconfirmed.add(
            r.userId,
          ); // a member the server lists is never trusted without a human
          continue;
        case PinCheck.matches:
          break;
      }
      byFolder
          .putIfAbsent(r.folderId, () => [])
          .add(
            await WrappedFolderKeys.wrap(
              keys,
              folderId: r.folderId,
              recipientPublicKey: publicKey,
              userId: r.userId,
              withSecret: r.secret,
            ),
          );
    }
    for (final MapEntry(key: folderId, value: wraps) in byFolder.entries) {
      await api.putFolderKeys(
        folderId,
        version: wraps.first.version,
        wrapped: wraps,
      );
    }
    return report;
  }
}
