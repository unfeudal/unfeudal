// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

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

/// A conflict copy's name: [suffix] appended, cut to the name limit of [kind].
void suffixName(Map<String, Object?> meta, ItemKind kind, String suffix) {
  if (meta['name'] case final String name) {
    final max = kind == ItemKind.snippet
        ? PayloadLimits.snippetName
        : PayloadLimits.name;
    meta['name'] = String.fromCharCodes('$name$suffix'.runes.take(max));
  }
}
