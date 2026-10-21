// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

void _requireRewritable(VaultEntry e) {
  if (e.orgId != null) throw StateError('org items go through OrgWriter');
  if (e.state != EntryState.ok) {
    throw StateError('${e.state.name} item is not rewritten');
  }
}

// The entry for item once openMeta opened its meta; null for a replayed payload. An unknown kind is not opened.
Future<VaultEntry?> _built(
  Item item,
  Future<OpenedPayload?> Function() openMeta, {
  required bool pending,
}) async {
  if (item.kind == ItemKind.unknown) {
    return VaultEntry(item, EntryState.unsupported, pending: pending);
  }
  try {
    final opened = await openMeta();
    if (opened == null) return null;
    return _entryOf(item, opened.json, pending: pending);
  } on _MissingFolderKey {
    return VaultEntry(
      item,
      EntryState.unreadable,
      pending: pending,
      awaitingKey: true,
    );
  } on Exception catch (e) {
    if (!isUnreadable(e)) rethrow;
    return VaultEntry(item, EntryState.unreadable, pending: pending);
  }
}

// The entry a reload would build for the queued item sealed from meta.
VaultEntry _written(Item item, Map<String, Object?> meta) {
  if (item.kind == ItemKind.unknown) {
    return VaultEntry(item, EntryState.unsupported, pending: true);
  }
  try {
    final json = jsonDecode(jsonEncode(meta)) as Map<String, Object?>;
    return _entryOf(item, json, pending: true);
  } on FormatException {
    return VaultEntry(item, EntryState.unreadable, pending: true);
  }
}

// ok, or readOnly for a newer schema; FormatException on a bad payload.
VaultEntry _entryOf(
  Item item,
  Map<String, Object?> json, {
  required bool pending,
}) {
  final schema = json['schemaVersion'];
  // A newer schema is shown but never rewritten.
  if (schema is int && schema > Payload.knownSchemaVersion) {
    return VaultEntry(item, EntryState.readOnly, meta: json, pending: pending);
  }
  // The typed model throws FormatException on a bad payload.
  _parseMeta(item.kind, json);
  return VaultEntry(item, EntryState.ok, meta: json, pending: pending);
}

void _parseMeta(ItemKind kind, Map<String, Object?> json) => switch (kind) {
  ItemKind.host => HostMeta.fromJson(json),
  ItemKind.identity => IdentityMeta.fromJson(json),
  ItemKind.folder => FolderMeta.fromJson(json),
  ItemKind.snippet => SnippetMeta.fromJson(json),
  ItemKind.knownHost => KnownHostMeta.fromJson(json),
  ItemKind.profile => ProfileMeta.fromJson(json),
  ItemKind.hostBinding => HostBindingMeta.fromJson(json),
  ItemKind.memberPin => MemberPinMeta.fromJson(json),
  ItemKind.unknown => null,
};
