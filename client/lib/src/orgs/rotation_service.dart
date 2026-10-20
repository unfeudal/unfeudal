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

/// `done`: folders whose rotation finished this run. `blocked`: readers to confirm before the rotation can go on.
typedef RotationReport = ({Set<String> done, Set<String> blocked});

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
      if (!block.isAdminOf(p.orgId)) continue;
      try {
        if (await rotate(block, p.orgId, p.folderId)) done.add(p.folderId);
      } on ApiException {
        // stays pending: retried on the next block
      } on NetworkException {
        // stays pending: retried on the next block
      }
    }
    return (done: done, blocked: blocked);
  }

  Future<bool> rotate(OrgBlock block, String orgId, String folderId) async {
    final pending = block.pendingRotations
        .where((p) => p.folderId == folderId)
        .firstOrNull;
    final held = keyring.current(folderId);
    if (held == null) return false; // this device cannot read the folder: another admin device rotates
    var keys = held;
    if (pending?.rotatedVersion == null ||
        held.version < pending!.rotatedVersion!) {
      final next = await _rotateKeys(
        block,
        orgId,
        folderId: folderId,
        held: held,
        removed: {...?pending?.removedUserIds},
      );
      if (next == null) return false;
      keys = next;
    }
    await writer.resealAll(
      mirror.items().where(
        (i) =>
            !i.purged &&
            (i.id == folderId ||
                (i.folderId == folderId && i.type != 'folder')) &&
            KeyIds.parseFolder(i.meta!.keyId)?.version != keys.version,
      ),
      keys,
    );
    await sync.syncNow();
    if (mirror.outbox().any(
      (e) => e.item.id == folderId || e.item.folderId == folderId,
    )) {
      return false;
    }
    await api.orgs.rotationDone(folderId);
    emit(const KeyRotated());
    return true;
  }

  // Null when a reader still needs confirming: nothing is sent then.
  Future<FolderKeys?> _rotateKeys(
    OrgBlock block,
    String orgId, {
    required String folderId,
    required FolderKeys held,
    required Set<String> removed,
  }) async {
    final wraps = <WrappedFolderKeys>[];
    final next = FolderKeys.generate(held.version + 1);
    for (final m in block.members.where(
      (m) =>
          m.orgId == orgId && !removed.contains(m.userId) && m.disabled != true,
    )) {
      final access = FolderKeyAccess.of(
        explainFromBlock(
          block,
          orgId,
          userId: m.userId,
          folderId: folderId,
        ).effective,
      );
      if (!access.hasMeta || m.publicKey == null) continue;
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
          withSecret: access.hasSecret,
        ),
      );
    }
    if (_blocked.isNotEmpty) {
      return null; // the server would refuse an incomplete rotation
    }
    final previous = [
      for (var v = 1; v <= held.version; v++) ?keyring.keyFor(folderId, v),
    ];
    await api.orgs.putFolderKeys(
      folderId,
      version: next.version,
      wrapped: wraps,
      history: await FolderKeyHistory.seal(next, previous, folderId: folderId),
    );
    await keyring.put(folderId, next);
    return next;
  }
}
