// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../events/app_events.dart';
import '../storage/local_mirror.dart';
import '../sync/sync_engine.dart';
import '../vault/folder_subtree.dart';
import '../vault/org_writer.dart';
import '../vault/vault.dart';
import 'block_permissions.dart';
import 'folder_keyring.dart';
import 'key_handoff.dart';
import 'member_pins.dart';
import 'rotation_service.dart';

/// The orgs of the signed-in user: each block arriving updates keys, entries, handoffs and rotations.
class OrgController extends ChangeNotifier {
  OrgController({
    required this.mirror,
    required this.vault,
    required this.api,
    required SyncEngine sync,
    required this.userId,
    required List<int> publicKey,
    required void Function(AppEvent) emit,
    required bool Function() online,
  }) : _sync = sync {
    keyring = FolderKeyring(mirror);
    pins = MemberPins(vault);
    writer = OrgWriter(
      vault: vault,
      mirror: mirror,
      keyring: keyring,
      api: api,
      block: () => block,
      userId: userId,
      publicKey: publicKey,
      online: online,
      emit: emit,
    );
    handoff = KeyHandoff(api: api, keyring: keyring, pins: pins);
    rotation = RotationService(
      api: api,
      keyring: keyring,
      pins: pins,
      writer: writer,
      sync: sync,
      mirror: mirror,
      userId: userId,
      emit: emit,
    );
  }

  final LocalMirror mirror;
  final Vault vault;
  final ApiClient api;
  final String userId;
  final SyncEngine _sync;
  late final FolderKeyring keyring;
  late final MemberPins pins;
  late final OrgWriter writer;
  late final KeyHandoff handoff;
  late final RotationService rotation;

  OrgBlock? block;

  /// Refused folder keys and changed member keys.
  final alerts = <String>{};
  HandoffReport? lastHandoff;
  RotationReport? lastRotation;

  /// The org shown in the shell; null is the personal vault.
  String? selected;

  /// Writes an item to the personal vault, or to [orgId]'s [folderId] through the org writer.
  Future<String> saveItem({
    required String type,
    String? id,
    String? orgId,
    String? folderId,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) => orgId == null
      ? vault.upsertItem(
          type: type,
          id: id,
          folderId: folderId,
          meta: meta,
          secret: secret,
        )
      : writer.upsert(
          type: type,
          id: id,
          target: OrgTarget(orgId, folderId),
          meta: meta,
          secret: secret,
        );

  /// Writes a folder to the personal vault, or to [orgId]: a new org folder is created, an existing one rewritten.
  Future<String> saveFolder(
    FolderMeta meta, {
    String? id,
    String? orgId,
    String? parentId,
  }) {
    if (orgId == null) {
      return vault.saveFolder(meta, id: id, parentId: parentId);
    }
    if (id == null) {
      return writer.createFolder(orgId: orgId, parentId: parentId, meta: meta);
    }
    return writer.upsert(
      type: 'folder',
      id: id,
      target: OrgTarget(orgId, parentId),
      meta: meta.toJson(),
    );
  }

  /// Whether [entry], a readable host or folder, may move into [folderId] (null: the root): not where it is,
  /// never into itself or below it, and in an org with edit on its current and its new parent.
  bool canMove(VaultEntry entry, String? folderId) {
    if (entry.state != EntryState.ok || entry.folderId == folderId) {
      return false;
    }
    final isFolder = entry.kind == ItemKind.folder;
    if (!isFolder && entry.kind != ItemKind.host) return false;
    if (isFolder &&
        folderId != null &&
        folderSubtree(vault, entry.id).contains(folderId)) {
      return false;
    }
    final orgId = entry.orgId;
    return orgId == null ||
        (writer.canEdit(orgId, entry.folderId) &&
            writer.canEdit(orgId, folderId));
  }

  /// Moves [entry] into [folderId] with the writes its editor makes, so an org item is sealed for its new place.
  Future<void> moveItem(VaultEntry entry, String? folderId) =>
      entry.kind == ItemKind.folder
      ? saveFolder(
          FolderMeta.fromJson(entry.meta),
          id: entry.id,
          orgId: entry.orgId,
          parentId: folderId,
        )
      : saveItem(
          type: 'host',
          id: entry.id,
          orgId: entry.orgId,
          folderId: folderId,
          meta: entry.meta!,
        );

  /// Moves an item to the trash, through the org writer for an org item.
  Future<void> trashItem(String id) =>
      _isOrgItem(id) ? writer.trash(id) : vault.trashItem(id);

  /// Takes an item out of the trash, through the org writer for an org item.
  Future<void> restoreItem(String id) =>
      _isOrgItem(id) ? writer.restore(id) : vault.restoreItem(id);

  bool _isOrgItem(String id) => vault.entry(id)?.orgId != null;
  SimpleKeyPair? _keyPair;

  List<OrgSummary> get orgs => block?.orgs ?? const [];

  void select(String? orgId) {
    selected = orgId;
    notifyListeners();
  }

  /// The cached block serves offline orgs until the next one arrives. Runs before the vault unlocks, so its
  /// one reload already shows the org items; [MemberPins.seed] follows that reload.
  Future<void> unlock(UnlockedAccount account) async {
    _keyPair = account.keyPair;
    await keyring.load(account.userKey);
    vault.keyring = keyring;
    if (mirror.kv(KvKey.orgBlock) case final raw?) {
      block = OrgBlock.fromJson(jsonDecode(raw));
    }
    notifyListeners();
  }

  void lock() {
    vault.keyring = null;
    keyring.close();
    _keyPair = null;
    block = null;
    alerts.clear();
  }

  Future<void> onBlock(OrgBlock arrived) async {
    final keyPair = _keyPair;
    // Locked while the round ran.
    if (keyPair == null) return;
    block = arrived;
    alerts.addAll(await keyring.apply(arrived, keyPair));
    await vault.reload();
    await pins.seed();
    if (arrived.orgs.any((o) => o.isAdmin)) {
      try {
        final report = lastHandoff = await handoff.run(arrived);
        alerts.addAll(report.alerts);
        lastRotation = await rotation.run(arrived);
      } on ApiException {
        // retried on the next block
      } on NetworkException {
        // retried on the next block
      }
    }
    notifyListeners();
  }

  /// Pins [member]'s key on this device; a changed key rotates every folder of the org they can view.
  Future<void> verifyMember(OrgMember member, {required bool verified}) async {
    final changed =
        pins.check(member.userId, member.publicKey!) == PinCheck.changed;
    await pins.pin(member.userId, member.publicKey!, verified: verified);
    alerts.remove(member.userId);
    await _sync.syncNow();
    final b = block;
    if (!changed || b == null) return;
    for (final n in b.folderTree.where((n) => n.orgId == member.orgId)) {
      final perms = permissions(
        member.orgId,
        n.folderId,
        userId: member.userId,
      );
      if (perms.contains(Permission.view)) {
        await rotation.rotate(b, member.orgId, n.folderId);
      }
    }
  }

  /// Rotates the pending folders now (the banner's button).
  Future<void> rotateNow() async {
    final b = block;
    if (b == null) return;
    // Each folder's failure stays pending inside the result.
    lastRotation = await rotation.run(b);
    notifyListeners();
  }

  Set<Permission> permissions(
    String orgId,
    String folderId, {
    String? userId,
  }) => explain(orgId, folderId, userId ?? this.userId).effective;

  Explanation explain(String orgId, String folderId, String userId) {
    final b = block;
    return b == null
        ? const Explanation({}, [])
        : explainFromBlock(b, orgId, userId: userId, folderId: folderId);
  }

  /// Whether [e] may be rewritten (restored): always for a personal item, `edit` on its parent folder for an org one.
  bool canEditEntry(VaultEntry e) =>
      e.orgId == null || writer.canEdit(e.orgId!, e.folderId);

  /// Whether [e]'s secrets may be shown: always for a personal item, `reveal` on its key folder for an org one.
  bool canReveal(VaultEntry e) {
    final item = e.item;
    return item.scope == ItemScope.personal ||
        permissions(item.orgId!, item.keyFolderId!).contains(Permission.reveal);
  }

  OrgSummary? byId(String? orgId) =>
      orgs.where((o) => o.id == orgId).firstOrNull;

  /// The org's members, by email.
  List<OrgMember> membersOf(String orgId) => [
    for (final m in block?.members ?? const <OrgMember>[])
      if (m.orgId == orgId) m,
  ]..sort((a, b) => a.email.compareTo(b.email));

  bool isAdmin(String orgId) => block?.isAdminOf(orgId) ?? false;

  /// The role alone, confirmed or not.
  bool isOwner(String orgId) => byId(orgId)?.knownRole == OrgRole.owner;
}
