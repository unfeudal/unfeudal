// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/orgs/folder_keyring.dart';
import 'package:unfeudal_client/src/orgs/member_pins.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/ledger_store.dart';
import 'package:unfeudal_client/src/sync/sync_engine.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'sync_harness.dart';

const testOrgId = '3c5e7a9b-1d2f-4e6a-8b0c-2d4f6a8c0e1a';

Future<({SimpleKeyPair pair, Uint8List publicKey})> memberKeys() async {
  final pair = await X25519().newKeyPair();
  return (
    pair: pair,
    publicKey: Uint8List.fromList((await pair.extractPublicKey()).bytes),
  );
}

Map<String, Object?> memberRow(
  String userId, {
  String role = 'member',
  String? status,
  List<int>? publicKey,
  String? email,
  bool? disabled,
}) => {
  'orgId': testOrgId,
  'userId': userId,
  'email': email ?? '${userId.substring(0, 8)}@example.org',
  'role': role,
  'status': ?status,
  if (publicKey != null) 'publicKey': b64(publicKey),
  'disabled': ?disabled,
};

Map<String, Object?> node(String folderId, [String? parentId]) => {
  'orgId': testOrgId,
  'folderId': folderId,
  'parentId': parentId,
};

Map<String, Object?> aclRow(
  String folderId,
  String principalId, {
  String type = 'user',
  List<String> allow = const [],
  List<String> deny = const [],
}) => {
  'orgId': testOrgId,
  'folderId': folderId,
  'principalType': type,
  'principalId': principalId,
  'allow': allow,
  'deny': deny,
};

Future<Map<String, Object?>> wrappedRow(
  FolderKeys keys,
  String folderId,
  List<int> publicKey, {
  bool secret = true,
}) async {
  final w = await WrappedFolderKeys.wrap(
    keys,
    folderId: folderId,
    recipientPublicKey: publicKey,
    withSecret: secret,
  );
  return {'folderId': folderId, ...w.toJson()};
}

Future<Map<String, Object?>> historyRow(
  FolderKeys current,
  List<FolderKeys> previous,
  String folderId,
) async => {
  'folderId': folderId,
  ...(await FolderKeyHistory.seal(
    current,
    previous,
    folderId: folderId,
  )).toJson(),
};

/// One org [testOrgId]; every list defaults to empty.
OrgBlock orgBlock({
  int cursor = 1,
  String role = 'member',
  String status = 'confirmed',
  Map<String, Object?> settings = const {},
  List<Map<String, Object?>> members = const [],
  List<Map<String, Object?>> teams = const [],
  List<Map<String, Object?>> acl = const [],
  List<Map<String, Object?>> folderTree = const [],
  List<Map<String, Object?>> wrappedKeys = const [],
  List<Map<String, Object?>> keyHistory = const [],
  List<Map<String, Object?>> keyRequests = const [],
  List<Map<String, Object?>> pendingRotations = const [],
  List<String> itemIds = const [],
}) => OrgBlock.fromJson({
  'orgCursor': cursor,
  'orgs': [
    {
      'id': testOrgId,
      'name': 'Acme',
      'role': role,
      'status': status,
      'settings': {'mascot': true, ...settings},
    },
  ],
  'members': members,
  'teams': teams,
  'acl': acl,
  'folderTree': folderTree,
  'wrappedKeys': wrappedKeys,
  'keyHistory': keyHistory,
  'keyRequests': keyRequests,
  'pendingRotations': pendingRotations,
  'itemIds': [...itemIds]..sort(),
});

/// An org item sealed with [keys] (the folder's keys; for a folder item, its own).
Future<Item> sealOrgItem(
  FolderKeys keys, {
  String? id,
  String type = 'host',
  String? folderId,
  String orgId = testOrgId,
  required Map<String, Object?> meta,
  Map<String, Object?>? secret,
  int seq = 1,
  int revision = 1,
  bool deleted = false,
}) async {
  final itemId = id ?? newId();
  final keyFolder = type == 'folder' ? itemId : folderId!;
  PayloadAad aad(PayloadPart p) => PayloadAad(
    itemId: itemId,
    part: p,
    type: type,
    scope: ItemScope.org,
    orgId: orgId,
    folderId: folderId,
  );
  return Item.fromJson({
    'id': itemId,
    'type': type,
    'scope': 'org',
    'orgId': orgId,
    'folderId': folderId,
    'schemaVersion': 1,
    'revision': revision,
    'deleted': deleted,
    'meta': (await PayloadCrypto.seal(
      aad(PayloadPart.meta),
      meta,
      keys.metaKey,
      keyId: KeyIds.folder(keyFolder, keys.version, PayloadPart.meta),
      seq: seq,
    )).toJson(),
    'secret': secret == null
        ? null
        : (await PayloadCrypto.seal(
            aad(PayloadPart.secret),
            secret,
            keys.secretKey!,
            keyId: KeyIds.folder(keyFolder, keys.version, PayloadPart.secret),
            seq: seq,
          )).toJson(),
    'createdAt': iso(DateTime.utc(2026, 10, 14)),
    'updatedAt': iso(DateTime.utc(2026, 10, 14)),
    'updatedBy': newId(),
    'updatedDevice': newId(),
  });
}

/// A signed-in client wired like AppState does for orgs: mirror, sync engine, vault with keyring, pins.
class ClientOrg {
  ClientOrg._(
    this.h,
    this.api,
    this.mirror,
    this.sync,
    this.vault,
    this.keyring,
    this.pins,
    this.userId,
    this.keyPair,
    this.publicKey,
  );

  final SyncHarness h;
  final ApiClient api;
  final LocalMirror mirror;
  final SyncEngine sync;
  final Vault vault;
  final FolderKeyring keyring;
  final MemberPins pins;
  final String userId;
  final SimpleKeyPair keyPair;
  final Uint8List publicKey;
  final events = <AppEvent>[];

  static Future<ClientOrg> start() async {
    final h = SyncHarness();
    final login = await h.signIn();
    final acc = login.account.account!;
    final api = ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken;
    final mirror = LocalMirror.inMemory();
    final sync = SyncEngine(api: api, mirror: mirror, deviceId: login.deviceId);
    final vault = Vault(
      mirror: mirror,
      ledger: LedgerStore(mirror),
      write: (items) async => mirror.enqueueAll(items),
    );
    await vault.unlock(acc.unlocked.userKey);
    final keyring = FolderKeyring(mirror);
    await keyring.load(acc.unlocked.userKey);
    vault.keyring = keyring;
    h.orgMembers[testOrgId] = {login.account.userId};
    return ClientOrg._(
      h,
      api,
      mirror,
      sync,
      vault,
      keyring,
      MemberPins(vault),
      login.account.userId,
      acc.unlocked.keyPair,
      Uint8List.fromList(acc.bundle.publicKey),
    );
  }

  /// My own row of the block.
  Map<String, Object?> me({String role = 'admin'}) => memberRow(
    userId,
    role: role,
    status: role == 'member' ? null : 'confirmed',
    publicKey: role == 'member' ? null : publicKey,
  );
}
