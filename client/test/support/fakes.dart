// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/ledger_store.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

final testUserId = newId();
final testDeviceId = newId();

Envelope fakeEnvelope([String keyId = 'user']) => Envelope.fromJson({
  'v': 1,
  'alg': 'xchacha20poly1305',
  'keyId': keyId,
  'nonce': b64(Uint8List(24)),
  'ct': b64(Uint8List(16)),
});

/// A wire item whose payloads are not meant to be opened (mirror and engine tests).
Item wireItem(
  String id, {
  int revision = 1,
  String type = 'host',
  bool deleted = false,
  bool purged = false,
  String? folderId,
  String? updatedDevice,
}) => Item.fromJson({
  'id': id,
  'type': type,
  'scope': 'personal',
  'orgId': null,
  'folderId': folderId,
  'schemaVersion': 1,
  'revision': revision,
  'deleted': deleted || purged,
  if (purged) 'purged': true,
  'meta': purged ? null : fakeEnvelope().toJson(),
  'secret': null,
  'createdAt': iso(DateTime.utc(2026, 10, 1)),
  'updatedAt': iso(DateTime.utc(2026, 10, 14)),
  'updatedBy': testUserId,
  'updatedDevice': updatedDevice ?? testDeviceId,
});

/// A personal item sealed as another device (or the server) holds it.
Future<Item> sealItem(
  Uint8List key, {
  String? id,
  String type = 'host',
  String? folderId,
  required Map<String, Object?> meta,
  Map<String, Object?>? secret,
  int seq = 1,
  int revision = 1,
  bool deleted = false,
  DateTime? createdAt,
}) async {
  final itemId = id ?? newId();
  PayloadAad aad(PayloadPart p) => PayloadAad(
    itemId: itemId,
    part: p,
    type: type,
    scope: ItemScope.personal,
    orgId: null,
    folderId: folderId,
  );
  return Item.fromJson({
    'id': itemId,
    'type': type,
    'scope': 'personal',
    'orgId': null,
    'folderId': folderId,
    'schemaVersion': 1,
    'revision': revision,
    'deleted': deleted,
    'meta': (await PayloadCrypto.seal(
      aad(PayloadPart.meta),
      meta,
      key,
      KeyIds.user,
      seq: seq,
    )).toJson(),
    'secret': secret == null
        ? null
        : (await PayloadCrypto.seal(
            aad(PayloadPart.secret),
            secret,
            key,
            KeyIds.user,
            seq: seq,
          )).toJson(),
    'createdAt': iso(createdAt ?? DateTime.utc(2026, 10, 14)),
    'updatedAt': iso(DateTime.utc(2026, 10, 14)),
    'updatedBy': testUserId,
    'updatedDevice': newId(),
  });
}

Map<String, Object?> hostJson(
  String name, {
  String address = '10.0.0.5',
  int? port,
  String? user,
  String? identityId,
  List<String> tags = const [],
}) => {
  'schemaVersion': 1,
  'name': name,
  'address': address,
  'port': ?port,
  'user': user,
  'identityId': identityId,
  'tags': tags,
  'notes': null,
  'startupCommand': null,
};

Map<String, Object?> folderJson(
  String name, {
  int? port,
  String? user,
  String? identityId,
}) => {
  'schemaVersion': 1,
  'name': name,
  'defaults': {'port': port, 'user': user, 'identityId': identityId},
};

/// Vault over [mirror] whose writes go straight to the outbox.
Future<Vault> testVault(Uint8List key, LocalMirror mirror) async {
  final v = Vault(
    mirror: mirror,
    ledger: LedgerStore(mirror),
    write: (item) async =>
        mirror.enqueue(item, baseRevision: item.revision ?? 0),
  );
  await v.unlock(key);
  return v;
}

/// The server accepts every queued write as-is.
List<Item> confirmOutbox(LocalMirror m) => [
  for (final e in m.outbox())
    () {
      final stored = Item.fromJson(
        e.item.toJson()
          ..['revision'] = e.baseRevision + 1
          ..['createdAt'] = iso(
            m.item(e.item.id)?.createdAt ?? DateTime.utc(2026, 10, 15),
          )
          ..['updatedAt'] = iso(DateTime.utc(2026, 10, 15))
          ..['updatedBy'] = testUserId
          ..['updatedDevice'] = testDeviceId,
      );
      m
        ..upsertItems([stored])
        ..removeOutbox(e.item.id);
      return stored;
    }(),
];
