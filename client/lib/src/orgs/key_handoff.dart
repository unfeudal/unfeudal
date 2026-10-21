// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import 'block_permissions.dart';
import 'folder_keyring.dart';
import 'member_pins.dart';

/// [unconfirmed]: not pinned on this device, the admin confirms them (safety code dialog).
/// [alerts]: pinned key changed, never sealed to.
typedef HandoffReport = ({Set<String> unconfirmed, Set<String> alerts});

class KeyHandoff {
  KeyHandoff({required this.api, required this.keyring, required this.pins});
  final ApiClient api;
  final FolderKeyring keyring;
  final MemberPins pins;

  Future<HandoffReport> run(OrgBlock block) async {
    final HandoffReport report = (unconfirmed: {}, alerts: {});
    final byFolder = <String, List<WrappedFolderKeys>>{};
    for (final request in block.keyRequests) {
      if (!block.isAdminOf(request.orgId)) continue;
      final keys = keyring.current(request.folderId);
      // Not held here: another admin device answers.
      if (keys == null || keys.version != request.version) {
        continue;
      }
      final member = block.members
          .where((m) => m.orgId == request.orgId && m.userId == request.userId)
          .firstOrNull;
      final publicKey = member?.publicKey;
      // Never a wrap for a disabled member.
      if (publicKey == null || member!.disabled == true) {
        continue;
      }
      switch (pins.check(request.userId, publicKey)) {
        case PinCheck.changed:
          report.alerts.add(request.userId);
          continue;
        case PinCheck.unpinned:
          // A member the server lists is never trusted without a human.
          report.unconfirmed.add(request.userId);
          continue;
        case PinCheck.matches:
          break;
      }
      byFolder
          .putIfAbsent(request.folderId, () => [])
          .add(
            await WrappedFolderKeys.wrap(
              keys,
              folderId: request.folderId,
              recipientPublicKey: publicKey,
              userId: request.userId,
              withSecret: request.needsSecret,
            ),
          );
    }
    for (final MapEntry(key: folderId, value: wraps) in byFolder.entries) {
      await api.orgs.putFolderKeys(
        folderId,
        version: wraps.first.version,
        wrapped: wraps,
      );
    }
    return report;
  }
}
