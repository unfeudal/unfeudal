// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'org_writer.dart';
import 'vault.dart';

/// Synced snippets of the vault, personal or org alike; org ones are written through [writer].
class SnippetStore {
  SnippetStore(this.vault, {this.writer});

  final Vault vault;
  final OrgWriter? writer;

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

  /// Checks the limits first; an edit stays where it is, a new snippet goes to [target] (personal when null).
  Future<String> save(SnippetMeta meta, {String? id, OrgTarget? target}) async {
    final parsed = SnippetMeta.fromJson(meta.toJson()).toJson();
    final current = id == null ? null : vault.entry(id);
    final org = current == null
        ? target
        : current.orgId == null
        ? null
        : OrgTarget(current.orgId!, current.folderId);
    if (org != null) {
      return writer!.upsert(type: 'snippet', id: id, target: org, meta: parsed);
    }
    return vault.upsertItem(
      type: 'snippet',
      id: id,
      folderId: current?.folderId,
      meta: parsed,
    );
  }

  Future<void> delete(String id) =>
      vault.entry(id)?.orgId == null ? vault.trashItem(id) : writer!.trash(id);
}
