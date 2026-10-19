// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'vault.dart';

/// Synced snippets of the vault, personal or org alike.
class SnippetStore {
  SnippetStore(this.vault);

  final Vault vault;

  /// Readable snippets matching [query] (name, command or tag, any case), sorted by name; one that does not
  /// parse is skipped.
  List<({String id, SnippetMeta meta})> list({String query = ''}) {
    final q = query.trim().toLowerCase();
    final out = <({String id, SnippetMeta meta})>[];
    for (final e in vault.ofKind(ItemKind.snippet)) {
      if (e.state != EntryState.ok) continue;
      final SnippetMeta meta;
      try {
        meta = SnippetMeta.fromJson(e.meta);
      } on FormatException {
        continue;
      }
      if (q.isEmpty ||
          meta.name.toLowerCase().contains(q) ||
          meta.command.toLowerCase().contains(q) ||
          meta.tags.any((t) => t.toLowerCase().contains(q))) {
        out.add((id: e.id, meta: meta));
      }
    }
    return out..sort(
      (a, b) => a.meta.name.toLowerCase().compareTo(b.meta.name.toLowerCase()),
    );
  }

  /// Checks the limits first; an edit stays in its folder.
  Future<String> save(SnippetMeta meta, {String? id}) async {
    final parsed = SnippetMeta.fromJson(meta.toJson());
    return vault.upsertItem(
      type: 'snippet',
      id: id,
      folderId: id == null ? null : vault.entry(id)?.folderId,
      meta: parsed.toJson(),
    );
  }

  Future<void> delete(String id) => vault.trashItem(id);
}
