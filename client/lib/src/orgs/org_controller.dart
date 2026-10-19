// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../events/app_events.dart';
import '../storage/local_mirror.dart';
import '../sync/sync_engine.dart';
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
  }) {
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
      write: sync.write,
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
  late final FolderKeyring keyring;
  late final MemberPins pins;
  late final OrgWriter writer;
  late final KeyHandoff handoff;
  late final RotationService rotation;

  OrgBlock? block;
  final alerts = <String>{}; // refused folder keys and changed member keys
  HandoffReport? lastHandoff;
  RotationReport? lastRotation;

  /// The org shown in the shell; null is the personal vault.
  String? selected;
  SimpleKeyPair? _keyPair;

  List<OrgSummary> get orgs => block?.orgs ?? const [];

  void select(String? orgId) {
    selected = orgId;
    notifyListeners();
  }

  /// The cached block serves offline orgs until the next one arrives.
  Future<void> unlock(UnlockedAccount account) async {
    _keyPair = account.keyPair;
    await keyring.load(account.userKey);
    vault.keyring = keyring;
    if (mirror.getKv(KvKey.orgBlock) case final raw?) {
      block = OrgBlock.fromJson(jsonDecode(raw));
    }
    await vault.reload();
    pins.seed();
    notifyListeners();
  }

  void lock() {
    vault.keyring = null;
    keyring.close();
    _keyPair = null;
    block = null;
    alerts.clear();
  }

  Future<void> onBlock(OrgBlock b) async {
    final keyPair = _keyPair;
    if (keyPair == null) return; // locked while the round ran
    block = b;
    alerts.addAll(await keyring.apply(b, keyPair));
    await vault.reload();
    pins.seed();
    if (b.orgs.any((o) => o.isAdmin)) {
      try {
        final report = lastHandoff = await handoff.run(b);
        alerts.addAll(report.alerts);
        lastRotation = await rotation.run(b);
      } on ApiException {
        // retried on the next block
      } on NetworkException {
        // retried on the next block
      }
    }
    notifyListeners();
  }

  /// Rotates the pending folders now (the banner's button).
  Future<void> rotateNow() async {
    final b = block;
    if (b == null) return;
    lastRotation = await rotation.run(
      b,
    ); // each folder's failure stays pending inside
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
        : explainFromBlock(b, orgId, userId, folderId);
  }

  OrgSummary? byId(String? orgId) =>
      orgs.where((o) => o.id == orgId).firstOrNull;

  /// The org's members, by email.
  List<OrgMember> membersOf(String orgId) => [
    for (final m in block?.members ?? const <OrgMember>[])
      if (m.orgId == orgId) m,
  ]..sort((a, b) => a.email.compareTo(b.email));

  bool isAdmin(String orgId) => byId(orgId)?.isAdmin ?? false;

  /// The role alone, confirmed or not.
  bool isOwner(String orgId) => byId(orgId)?.role == OrgRole.owner.name;
}
