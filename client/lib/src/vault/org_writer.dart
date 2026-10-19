// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../events/app_events.dart';
import '../orgs/block_permissions.dart';
import '../orgs/folder_keyring.dart';
import '../storage/local_mirror.dart';
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
class OrgWriter {
  OrgWriter({
    required this.vault,
    required this.mirror,
    required this.keyring,
    required this.api,
    required this._block,
    required this.userId,
    required this.publicKey,
    required this._write,
    required this._online,
    required this._emit,
  });

  final Vault vault;
  final LocalMirror mirror;
  final FolderKeyring keyring;
  final ApiClient api;
  final String userId;
  final List<int> publicKey;
  final OrgBlock? Function() _block;
  final Future<void> Function(Item) _write;
  final bool Function() _online;
  final void Function(AppEvent) _emit;

  Future<String> upsert({
    required String type,
    String? id,
    required OrgTarget target,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) async {
    final current = id == null ? null : vault.entry(id);
    final moved = current != null && current.folderId != target.folderId;
    if ((type != 'folder' && target.folderId == null) ||
        !canEdit(target.orgId, target.folderId) ||
        (moved && !canEdit(target.orgId, current.folderId))) {
      throw const OrgWriteRefused(OrgWriteRefusal.noEdit);
    }
    final itemId = id ?? newId();
    // A move re-seals both parts, and so does an edit whose queued write still carries an unsent secret.
    if (current != null && secret == null && (moved || _queuedSecret(itemId))) {
      secret = await _currentSecret(itemId);
    }
    await _send(
      await _seal(
        id: itemId,
        type: type,
        orgId: target.orgId,
        folderId: target.folderId,
        deleted: current?.item.deleted ?? false,
        revision: current?.item.revision ?? 0,
        meta: meta,
        secret: secret,
      ),
    );
    return itemId;
  }

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
    final item = await _seal(
      id: id,
      type: 'folder',
      orgId: orgId,
      folderId: parentId,
      deleted: false,
      revision: 0,
      meta: meta.toJson(),
      sealWith: keys,
    );
    mirror.upsertItems([await api.putItem(item, ifMatch: 0)]);
    await api.putFolderKeys(
      id,
      version: 1,
      wrapped: [
        await WrappedFolderKeys.wrap(
          keys,
          folderId: id,
          recipientPublicKey: publicKey,
          userId: userId,
        ),
      ],
    );
    await keyring.put(id, keys);
    await vault.reload();
    _emit(SharedVaultCreated(orgId: orgId));
    return id;
  }

  Future<void> trash(String id) => _setDeleted(id, true);

  Future<void> restore(String id) => _setDeleted(id, false);

  /// Both parts opened with the keys they were sealed with, sealed again with [keys] (rotation).
  Future<Item> reseal(Item item, FolderKeys keys) async {
    final resealed = await _seal(
      id: item.id,
      type: item.type,
      orgId: item.orgId!,
      folderId: item.folderId,
      deleted: item.deleted,
      revision: item.revision ?? 0,
      meta: await _open(item, PayloadPart.meta),
      secret: item.secret == null
          ? null
          : await _open(item, PayloadPart.secret),
      sealWith: keys,
    );
    await _send(resealed);
    return resealed;
  }

  /// A new id in the same org folder, sealed at the folder's current version, revision 0. Null for an unknown type.
  Future<Item?> conflictCopy(Item mine, {required String suffix}) async {
    if (mine.kind == ItemKind.unknown) return null;
    final meta = await _open(mine, PayloadPart.meta);
    final secret = mine.secret == null
        ? null
        : await _open(mine, PayloadPart.secret);
    if (meta['name'] case final String name) {
      final max = mine.kind == ItemKind.snippet
          ? PayloadLimits.snippetName
          : PayloadLimits.name;
      meta['name'] = String.fromCharCodes('$name$suffix'.runes.take(max));
    }
    return _seal(
      id: newId(),
      type: mine.type,
      orgId: mine.orgId!,
      folderId: mine.folderId,
      deleted: false,
      revision: 0,
      meta: meta,
      secret: secret,
    );
  }

  /// `edit` on [folderId] (the org root: a confirmed owner or admin); the UI asks it before offering a write.
  bool canEdit(String orgId, String? folderId) {
    final block = _block();
    if (block == null) return false;
    if (folderId == null) {
      final org = block.orgs.where((o) => o.id == orgId).firstOrNull;
      return org != null &&
          org.status == 'confirmed' &&
          (org.role == 'owner' || org.role == 'admin');
    }
    return explainFromBlock(
      block,
      orgId,
      userId,
      folderId,
    ).effective.contains(Permission.edit);
  }

  /// Same envelopes with `deleted` flipped; `secret: null` keeps the stored one.
  Future<void> _setDeleted(String id, bool deleted) async {
    final current =
        vault.entry(id) ??
        (throw ArgumentError.value(id, 'id', 'unknown item'));
    if (current.orgId == null || current.state != EntryState.ok) {
      throw StateError('not a readable org item');
    }
    if (!canEdit(current.orgId!, current.folderId)) {
      throw const OrgWriteRefused(OrgWriteRefusal.noEdit);
    }
    final json = current.item.toJson()
      ..removeWhere((k, _) => _serverSet.contains(k))
      ..['deleted'] = deleted;
    if (!_queuedSecret(id)) json['secret'] = null;
    await _send(Item.fromJson(json));
  }

  static const _serverSet = {
    'purged',
    'createdAt',
    'updatedAt',
    'updatedBy',
    'updatedDevice',
  };

  bool _queuedSecret(String id) =>
      mirror.outbox().any((e) => e.item.id == id && e.item.secret != null);

  Future<Map<String, Object?>?> _currentSecret(String id) async {
    final queued = mirror
        .outbox()
        .where((e) => e.item.id == id)
        .firstOrNull
        ?.item;
    final holder = queued?.secret != null ? queued! : mirror.item(id);
    if (holder?.secret == null) return null;
    return _open(holder!, PayloadPart.secret);
  }

  /// Opens one part with the keyring key its keyId names; [OrgWriteRefusal.noSecretKey] or `noKey` when not held.
  Future<Map<String, Object?>> _open(Item item, PayloadPart part) async {
    final envelope = part == PayloadPart.meta ? item.meta! : item.secret!;
    final id = KeyIds.parseFolder(envelope.keyId);
    final keys = id == null ? null : keyring.keyFor(id.folderId, id.version);
    final Uint8List? key = part == PayloadPart.meta
        ? keys?.metaKey
        : keys?.secretKey;
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

  Future<void> _send(Item item) async {
    await _write(item);
    await vault.reload();
  }

  Future<Item> _seal({
    required String id,
    required String type,
    required String orgId,
    required String? folderId,
    required bool deleted,
    required int revision,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
    FolderKeys? sealWith,
  }) async {
    final keyFolder = type == 'folder' ? id : folderId!;
    final keys =
        sealWith ??
        keyring.current(keyFolder) ??
        (throw const OrgWriteRefused(OrgWriteRefusal.noKey));
    if (secret != null && keys.secretKey == null) {
      throw const OrgWriteRefused(OrgWriteRefusal.noSecretKey);
    }
    final seq = vault.ledger.nextSeq(id); // one seq for both parts of one write
    PayloadAad aad(PayloadPart p) => PayloadAad(
      itemId: id,
      part: p,
      type: type,
      scope: ItemScope.org,
      orgId: orgId,
      folderId: folderId,
    );
    // a rewrite keeps the wire item's unknown fields and schemaVersion as read
    final current = vault.entry(id)?.item;
    return Item(
      id: id,
      type: type,
      scope: ItemScope.org,
      orgId: orgId,
      folderId: folderId,
      schemaVersion: current?.schemaVersion ?? 1,
      extra: current?.extra ?? const {},
      revision: revision,
      deleted: deleted,
      meta: await PayloadCrypto.seal(
        aad(PayloadPart.meta),
        meta,
        keys.metaKey,
        KeyIds.folder(keyFolder, keys.version, PayloadPart.meta),
        seq: seq,
      ),
      secret: secret == null
          ? null
          : await PayloadCrypto.seal(
              aad(PayloadPart.secret),
              secret,
              keys.secretKey!,
              KeyIds.folder(keyFolder, keys.version, PayloadPart.secret),
              seq: seq,
            ),
    );
  }
}
