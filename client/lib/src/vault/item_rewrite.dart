// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../orgs/folder_keyring.dart';
import '../storage/local_mirror.dart';

/// Same envelopes with `deleted` flipped: `deleted` is not in the AAD, so nothing is re-sealed; `secret: null`
/// keeps the stored one, and a queued secret not stored yet is sent again as is.
Item withDeleted(LocalMirror mirror, Item item, bool deleted) {
  final json = item.toJson()
    ..removeWhere((k, _) => _serverSet.contains(k))
    ..['deleted'] = deleted;
  if (!hasQueuedSecret(mirror, item.id)) json['secret'] = null;
  return Item.fromJson(json);
}

const _serverSet = {
  'purged',
  'createdAt',
  'updatedAt',
  'updatedBy',
  'updatedDevice',
};

bool hasQueuedSecret(LocalMirror mirror, String id) =>
    mirror.outbox().any((e) => e.item.id == id && e.item.secret != null);

/// The item holding the current secret of [id]: the queued write if it carries a secret, else the server row.
/// Null when neither has one.
({Item item, bool queued})? secretHolder(LocalMirror mirror, String id) {
  final queued = mirror
      .outbox()
      .where((e) => e.item.id == id)
      .firstOrNull
      ?.item;
  if (queued?.secret != null) return (item: queued!, queued: true);
  final stored = mirror.item(id);
  return stored?.secret == null ? null : (item: stored!, queued: false);
}

/// A move re-seals both parts (the server refuses a moved item without its secret), and so does an edit
/// of an item whose queued write still carries a secret the server has not stored yet.
bool resealsSecret(LocalMirror mirror, Item current, String? folderId) =>
    current.folderId != folderId || hasQueuedSecret(mirror, current.id);

/// The keyring key of the folder and version [envelope]'s keyId names, for [part]. Null = not held.
Uint8List? folderPartKey(
  FolderKeyring? keyring,
  Envelope envelope,
  PayloadPart part,
) {
  final id = KeyIds.parseFolder(envelope.keyId);
  if (id == null || id.part != part) return null;
  final keys = keyring?.keyFor(id.folderId, id.version);
  return part == PayloadPart.meta ? keys?.metaKey : keys?.secretKey;
}

/// The key and keyId sealing [PayloadPart].
typedef SealKeys = ({Uint8List key, String keyId}) Function(PayloadPart part);

/// Both parts sealed with one [seq] under the AAD of the new placement. A rewrite keeps [current]'s
/// unknown fields and schemaVersion as read.
Future<Item> sealPayloads({
  required Item? current,
  required String id,
  required String type,
  required String? orgId,
  required String? folderId,
  required bool deleted,
  required int revision,
  required int seq,
  required Map<String, Object?> meta,
  required Map<String, Object?>? secret,
  required SealKeys keyFor,
}) async {
  final scope = orgId == null ? ItemScope.personal : ItemScope.org;
  Future<Envelope> sealPart(PayloadPart part, Map<String, Object?> json) {
    final (:key, :keyId) = keyFor(part);
    return PayloadCrypto.seal(
      PayloadAad(
        itemId: id,
        part: part,
        type: type,
        scope: scope,
        orgId: orgId,
        folderId: folderId,
      ),
      json,
      key,
      keyId,
      seq: seq,
    );
  }

  return Item(
    id: id,
    type: type,
    orgId: orgId,
    folderId: folderId,
    schemaVersion: current?.schemaVersion ?? 1,
    extra: current?.extra ?? const {},
    revision: revision,
    deleted: deleted,
    meta: await sealPart(PayloadPart.meta, meta),
    secret: secret == null ? null : await sealPart(PayloadPart.secret, secret),
  );
}

/// A conflict copy's parts: both opened by [open], the name suffixed and cut to the limit of its kind.
/// Null for an unknown type.
Future<({Map<String, Object?> meta, Map<String, Object?>? secret})?>
conflictCopyParts(
  Item mine,
  String suffix,
  Future<Map<String, Object?>> Function(PayloadPart) open,
) async {
  if (mine.kind == ItemKind.unknown) return null;
  final meta = await open(PayloadPart.meta);
  final secret = mine.secret == null ? null : await open(PayloadPart.secret);
  if (meta['name'] case final String name) {
    final max = mine.kind == ItemKind.snippet
        ? PayloadLimits.snippetName
        : PayloadLimits.name;
    meta['name'] = String.fromCharCodes('$name$suffix'.runes.take(max));
  }
  return (meta: meta, secret: secret);
}
