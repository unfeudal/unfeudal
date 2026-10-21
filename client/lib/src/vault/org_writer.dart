// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../events/app_events.dart';
import '../orgs/block_permissions.dart';
import '../orgs/folder_keyring.dart';
import '../storage/local_mirror.dart';
import 'item_rewrite.dart';
import 'vault.dart';

/// Where an org item goes: [folderId] null is the org root (only for a folder item).
class OrgTarget {
  const OrgTarget(this.orgId, this.folderId);
  final String orgId;
  final String? folderId;
}

enum OrgWriteRefusal { noEdit, noKey, noSecretKey, needsServer }

class OrgWriteRefused implements Exception {
  const OrgWriteRefused(this.reason);
  final OrgWriteRefusal reason;

  @override
  String toString() => 'OrgWriteRefused(${reason.name})';
}

/// Org writes: checked against the cached block, sealed with the folder keys at their current version.
class OrgWriter implements WriteScope {
  OrgWriter({
    required this._vault,
    required this._mirror,
    required this._keyring,
    required this._api,
    required this._block,
    required this._userId,
    required this._publicKey,
    required this._online,
    required this._emit,
  });

  final Vault _vault;
  final LocalMirror _mirror;
  final FolderKeyring _keyring;
  final ApiClient _api;
  final String _userId;
  final List<int> _publicKey;
  final OrgBlock? Function() _block;
  final bool Function() _online;
  final void Function(AppEvent) _emit;

  Future<String> upsert({
    required String type,
    String? id,
    required OrgTarget target,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) => _vault.rewrite(
    this,
    type: type,
    id: id,
    orgId: target.orgId,
    folderId: target.folderId,
    meta: meta,
    secret: secret,
  );

  /// Needs the server: the item, then the first keys wrapped for the creator.
  Future<String> createFolder({
    required String orgId,
    String? parentId,
    required FolderMeta meta,
  }) async {
    if (!_online()) throw const OrgWriteRefused(OrgWriteRefusal.needsServer);
    if (!canEdit(orgId, parentId)) {
      throw const OrgWriteRefused(OrgWriteRefusal.noEdit);
    }
    final id = newId();
    final keys = FolderKeys.generate(1);
    final item = await _vault.sealer.sealItem(
      id: id,
      type: 'folder',
      orgId: orgId,
      folderId: parentId,
      meta: meta.toJson(),
      keyFor: _keysOf(id, keys),
    );
    _mirror.upsertItems([await _api.putItem(item, ifMatch: 0)]);
    await _api.orgs.putFolderKeys(
      id,
      version: 1,
      wrapped: [
        await WrappedFolderKeys.wrap(
          keys,
          folderId: id,
          recipientPublicKey: _publicKey,
          userId: _userId,
        ),
      ],
    );
    await _keyring.put(id, keys);
    await _vault.reload();
    _emit(const SharedVaultCreated());
    return id;
  }

  Future<void> trash(String id) => _vault.setDeleted(this, id, deleted: true);

  Future<void> restore(String id) =>
      _vault.setDeleted(this, id, deleted: false);

  /// Both parts of each item opened with the keys they were sealed with, sealed again with [keys] (rotation);
  /// the vault reloads once, after the last.
  Future<void> resealAll(Iterable<Item> items, FolderKeys keys) async {
    final sealed = <Item>[];
    try {
      for (final item in items) {
        final meta = await _open(item, PayloadPart.meta);
        final secret = item.secret == null
            ? null
            : await _open(item, PayloadPart.secret);
        if (secret != null && keys.secretKey == null) {
          throw const OrgWriteRefused(OrgWriteRefusal.noSecretKey);
        }
        sealed.add(
          await _vault.sealer.sealItem(
            id: item.id,
            type: item.type,
            orgId: item.orgId!,
            folderId: item.folderId,
            deleted: item.deleted,
            revision: item.revision ?? 0,
            meta: meta,
            secret: secret,
            keyFor: _keysOf(
              keyFolderIdOf(
                type: item.type,
                id: item.id,
                folderId: item.folderId,
              )!,
              keys,
            ),
          ),
        );
      }
    } finally {
      // The items sealed before a refusal midway go too, and show; one commit and one round for all.
      if (sealed.isNotEmpty) await _vault.sendAll(sealed);
      await _vault.reload();
    }
  }

  /// A new id in the same org folder, sealed at the folder's current version, revision 0. Null for an unknown type.
  Future<Item?> conflictCopy(Item mine, {required String suffix}) =>
      _vault.sealer.conflictCopyIn(
        this,
        mine,
        suffix: suffix,
        orgId: mine.orgId!,
        folderId: mine.folderId,
      );

  /// `edit` on [folderId] (the org root: a confirmed owner or admin); the UI asks it before offering a write.
  bool canEdit(String orgId, String? folderId) {
    final block = _block();
    if (block == null) return false;
    if (folderId == null) {
      return block.isAdminOf(orgId);
    }
    return explainFromBlock(
      block,
      orgId,
      userId: _userId,
      folderId: folderId,
    ).effective.contains(Permission.edit);
  }

  @override
  void checkWrite(
    VaultEntry? current, {
    required String type,
    required String? orgId,
    required String? folderId,
  }) {
    final moved = current != null && current.folderId != folderId;
    if ((type != 'folder' && folderId == null) ||
        !canEdit(orgId!, folderId) ||
        (moved && !canEdit(orgId, current.folderId))) {
      throw const OrgWriteRefused(OrgWriteRefusal.noEdit);
    }
  }

  @override
  void checkDelete(VaultEntry current) {
    if (current.orgId == null || current.state != EntryState.ok) {
      throw StateError('not a readable org item');
    }
    if (!canEdit(current.orgId!, current.folderId)) {
      throw const OrgWriteRefused(OrgWriteRefusal.noEdit);
    }
  }

  /// No replay check here: org parts open with the keyring key their keyId names.
  @override
  Future<Map<String, Object?>> openPart(
    Item item,
    PayloadPart part, {
    required bool fromServer,
  }) => _open(item, part);

  @override
  SealKeys sealKeys({
    required String type,
    required String id,
    required String? folderId,
    required bool withSecret,
  }) {
    final keyFolder = keyFolderIdOf(type: type, id: id, folderId: folderId)!;
    final keys =
        _keyring.current(keyFolder) ??
        (throw const OrgWriteRefused(OrgWriteRefusal.noKey));
    if (withSecret && keys.secretKey == null) {
      throw const OrgWriteRefused(OrgWriteRefusal.noSecretKey);
    }
    return _keysOf(keyFolder, keys);
  }

  // Opens one part with the keyring key its keyId names; OrgWriteRefusal.noSecretKey or `noKey` when not held.
  Future<Map<String, Object?>> _open(Item item, PayloadPart part) async {
    final envelope = part == PayloadPart.meta ? item.meta! : item.secret!;
    final key = folderPartKey(_keyring, envelope, part);
    if (key == null) {
      throw OrgWriteRefused(
        part == PayloadPart.secret
            ? OrgWriteRefusal.noSecretKey
            : OrgWriteRefusal.noKey,
      );
    }
    return (await PayloadCrypto.open(
      PayloadAad.of(item, part),
      envelope,
      key,
    )).json;
  }

  static SealKeys _keysOf(String keyFolder, FolderKeys keys) =>
      (part) => (
        key: part == PayloadPart.meta ? keys.metaKey : keys.secretKey!,
        keyId: KeyIds.folder(keyFolder, keys.version, part),
      );
}
