// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

enum EntryState { ok, unreadable, unsupported, readOnly }

/// One item as shown: [meta] is the opened payload, [pending] a local write not yet confirmed,
/// [awaitingKey] an org item whose folder key version is not held.
class VaultEntry {
  const VaultEntry(
    this.item,
    this.state, {
    this.meta,
    this.pending = false,
    this.awaitingKey = false,
  });

  final Item item;
  final EntryState state;
  final Map<String, Object?>? meta;
  final bool pending;
  final bool awaitingKey;

  String get id => item.id;
  String? get orgId => item.orgId;
  String? get folderId => item.folderId;
  ItemKind get kind => item.kind;
  String? get name => switch (meta?['name']) {
    final String name => name,
    _ => null,
  };
}

/// What a rewrite depends on its scope: who may write, how the current parts open, which keys seal.
abstract interface class WriteScope {
  /// Throws unless [current] (null: a new item) may be written as [type] in [orgId]'s [folderId].
  void checkWrite(
    VaultEntry? current, {
    required String type,
    required String? orgId,
    required String? folderId,
  });

  /// Throws unless [current] may be trashed or restored.
  void checkDelete(VaultEntry current);

  /// The plaintext of [part]; a [fromServer] part is replay-checked where the scope does it.
  Future<Map<String, Object?>> openPart(
    Item item,
    PayloadPart part, {
    required bool fromServer,
  });

  /// The key and keyId sealing each part of item [id] in [folderId]; throws when one is not held.
  SealKeys sealKeys({
    required String type,
    required String id,
    required String? folderId,
    required bool withSecret,
  });
}

/// The personal `ok` entry with the smallest id among [entries] that pass [where]: the same on every device.
VaultEntry? winner(
  Iterable<VaultEntry> entries, [
  bool Function(VaultEntry e)? where,
]) {
  VaultEntry? best;
  for (final e in entries) {
    if (e.state != EntryState.ok || e.orgId != null) continue;
    if (where != null && !where(e)) continue;
    if (best == null || e.id.compareTo(best.id) < 0) best = e;
  }
  return best;
}

/// Orders entries by name, unnamed ones first.
int byName(VaultEntry a, VaultEntry b) =>
    (a.name ?? '').compareTo(b.name ?? '');
