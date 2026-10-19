// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../events/app_events.dart';
import '../storage/local_mirror.dart';
import '../sync/sync_engine.dart';
import '../vault/org_writer.dart';
import 'block_permissions.dart';
import 'folder_keyring.dart';
import 'member_pins.dart';

class RotationReport {
  RotationReport(this.done, this.blocked);
  final Set<String> done; // folders whose rotation finished this run
  final Set<String> blocked; // readers to confirm before the rotation can go on
}

/// Admin clients rotate a folder's keys when a reader lost access, then re-seal its items.
class RotationService {
  RotationService({
    required this.api,
    required this.keyring,
    required this.pins,
    required this.writer,
    required this.sync,
    required this.mirror,
    required this.userId,
    required this.emit,
  });

  final ApiClient api;
  final FolderKeyring keyring;
  final MemberPins pins;
  final OrgWriter writer;
  final SyncEngine sync;
  final LocalMirror mirror;
  final String userId;
  final void Function(AppEvent) emit;
  Set<String> _blocked = {};

  Future<RotationReport> run(OrgBlock block) async {
    final done = <String>{};
    final blocked = _blocked = {};
    for (final p in block.pendingRotations) {
      if (!block.orgs.any((o) => o.id == p.orgId && o.isAdmin)) continue;
      try {
        if (await rotate(block, p.orgId, p.folderId)) done.add(p.folderId);
      } on ApiException {
        // stays pending: retried on the next block
      } on NetworkException {
        // stays pending: retried on the next block
      }
    }
    return RotationReport(done, blocked);
  }

  // ponytail: re-seals one folder at a time; batch when a folder holds thousands of items.
  Future<bool> rotate(OrgBlock block, String orgId, String folderId) async {
    final pending = block.pendingRotations
        .where((p) => p.folderId == folderId)
        .firstOrNull;
    final held = keyring.current(folderId);
    if (held == null) return false; // this device cannot read the folder: another admin device rotates
    var keys = held;
    if (pending?.rotatedVersion == null ||
        held.version < pending!.rotatedVersion!) {
      final removed = {...?pending?.removedUserIds};
      final wraps = <WrappedFolderKeys>[];
      final next = FolderKeys.generate(held.version + 1);
      for (final m in block.members.where(
        (m) =>
            m.orgId == orgId &&
            !removed.contains(m.userId) &&
            m.disabled != true,
      )) {
        final perms = explainFromBlock(
          block,
          orgId,
          m.userId,
          folderId,
        ).effective;
        if (!perms.contains(Permission.view) || m.publicKey == null) continue;
        if (m.userId != userId &&
            pins.check(m.userId, m.publicKey!) != PinCheck.matches) {
          _blocked.add(m.userId); // unpinned: the admin confirms them first; changed: alert. Never pinned here.
          continue;
        }
        wraps.add(
          await WrappedFolderKeys.wrap(
            next,
            folderId: folderId,
            recipientPublicKey: m.publicKey!,
            userId: m.userId,
            withSecret: perms.contains(Permission.connect),
          ),
        );
      }
      if (_blocked.isNotEmpty) {
        return false; // the server would refuse an incomplete rotation
      }
      final previous = [
        for (var v = 1; v <= held.version; v++) ?keyring.keyFor(folderId, v),
      ];
      await api.putFolderKeys(
        folderId,
        version: next.version,
        wrapped: wraps,
        history: await FolderKeyHistory.seal(
          next,
          previous,
          folderId: folderId,
        ),
      );
      await keyring.put(folderId, next);
      keys = next;
    }
    for (final item in mirror.items().where(
      (i) =>
          !i.purged &&
          (i.id == folderId || (i.folderId == folderId && i.type != 'folder')),
    )) {
      if (KeyIds.parseFolder(item.meta!.keyId)?.version != keys.version) {
        await writer.reseal(item, keys);
      }
    }
    await sync.syncNow();
    if (mirror.outbox().any(
      (e) => e.item.id == folderId || e.item.folderId == folderId,
    )) {
      return false;
    }
    await api.rotationDone(folderId);
    emit(const KeyRotated());
    return true;
  }
}
