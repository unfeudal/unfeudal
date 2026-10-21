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

  Future<RotationReport> run(OrgBlock block) async {
    final done = <String>{};
    final blocked = <String>{};
    for (final p in block.pendingRotations) {
      if (!block.isAdminOf(p.orgId)) continue;
      try {
        if (await rotate(block, p.orgId, p.folderId, blocked: blocked)) {
          done.add(p.folderId);
        }
      } on ApiException {
        // stays pending: retried on the next block
      } on NetworkException {
        // stays pending: retried on the next block
      }
    }
    return (done: done, blocked: blocked);
  }

  /// Adds the readers to confirm before [folderId] can rotate to [blocked].
  Future<bool> rotate(
    OrgBlock block,
    String orgId,
    String folderId, {
    Set<String>? blocked,
  }) async {
    final pending = block.pendingRotations
        .where((p) => p.folderId == folderId)
        .firstOrNull;
    final held = keyring.current(folderId);
    // This device cannot read the folder: another admin device rotates it.
    if (held == null) return false;
    var keys = held;
    if (pending?.rotatedVersion == null ||
        held.version < pending!.rotatedVersion!) {
      final next = await _rotateKeys(
        block,
        orgId,
        folderId: folderId,
        held: held,
        blocked: blocked,
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
    Set<String>? blocked,
  }) async {
    final unconfirmed = <String>{};
    final wraps = <WrappedFolderKeys>[];
    final next = FolderKeys.generate(held.version + 1);
    // Readers come from current permissions, as the server checks: a removed member who regained access counts.
    for (final member in block.members.where(
      (m) => m.orgId == orgId && m.disabled != true,
    )) {
      final access = FolderKeyAccess.of(
        explainFromBlock(
          block,
          orgId,
          userId: member.userId,
          folderId: folderId,
        ).effective,
      );
      if (!access.hasMeta || member.publicKey == null) continue;
      if (member.userId != userId &&
          pins.check(member.userId, member.publicKey!) != PinCheck.matches) {
        // Unpinned: the admin confirms them first; changed: alert. Never pinned here.
        unconfirmed.add(member.userId);
        continue;
      }
      wraps.add(
        await WrappedFolderKeys.wrap(
          next,
          folderId: folderId,
          recipientPublicKey: member.publicKey!,
          userId: member.userId,
          withSecret: access.hasSecret,
        ),
      );
    }
    blocked?.addAll(unconfirmed);
    // The server would refuse an incomplete rotation.
    if (unconfirmed.isNotEmpty) return null;
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
