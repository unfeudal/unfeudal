// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../storage/local_mirror.dart';

/// Pulls the server's pages into the mirror and applies the org block's itemIds rule.
class ItemPuller {
  ItemPuller({
    required this.api,
    required this.mirror,
    required this.markChanged,
    required this.onOrgBlock,
  });

  final ApiClient api;
  final LocalMirror mirror;
  final void Function() markChanged;
  final Future<void> Function(OrgBlock block) onOrgBlock;
  bool _resyncing = false;

  Future<void> pull({bool full = false, bool acceptOlder = false}) async {
    var cursor = full ? 0 : int.parse(mirror.getKv(KvKey.cursor) ?? '0');
    var orgCursor = full ? 0 : int.parse(mirror.getKv(KvKey.orgCursor) ?? '0');
    final seen = <String>{};
    OrgBlock? arrived;
    // Ids received after the block's response: their seq is above its cursor.
    final later = <String>{};
    for (var more = true; more;) {
      // The page is parsed whole before anything is applied.
      final page = await api.sync(cursor: cursor, orgCursor: orgCursor);
      mirror.upsertItems(page.items, acceptOlder: acceptOlder);
      if (page.items.isNotEmpty) markChanged();
      seen.addAll(page.items.map((i) => i.id));
      if (arrived != null) later.addAll(page.items.map((i) => i.id));
      if (page.org case final org?) {
        mirror
          ..setKv(KvKey.orgBlock, jsonEncode(org.toJson()))
          ..setKv(KvKey.orgCursor, '${org.orgCursor}');
        orgCursor = org.orgCursor;
        arrived = org;
        markChanged();
        later.clear();
      }
      trace(
        TraceArea.sync,
        'pulled ${page.items.length} items, cursor $cursor → ${page.cursor}',
      );
      cursor = page.cursor;
      mirror.setKv(KvKey.cursor, '$cursor');
      more = page.more;
    }
    if (full) {
      // Replaced by the server's, only once the whole pull succeeded; queued items stay.
      final queued = mirror.outboxIds().toSet();
      _delete([
        for (final id in mirror.itemIds())
          if (!seen.contains(id) && !queued.contains(id)) id,
      ]);
    }
    if (arrived == null) return;
    final visible = arrived.itemIds.toSet();
    final queued = mirror.outboxIds().toSet();
    _delete([
      for (final id in mirror.itemIds(scope: ItemScope.org))
        if (!visible.contains(id) &&
            !queued.contains(id) &&
            !later.contains(id))
          id,
    ]);
    final held = mirror.itemIds();
    if (!full && !_resyncing && visible.any((id) => !held.contains(id))) {
      // Only once: a server that keeps listing a missing id cannot loop us.
      _resyncing = true;
      try {
        return await pull(full: true, acceptOlder: acceptOlder);
      } finally {
        _resyncing = false;
      }
    }
    await onOrgBlock(arrived);
  }

  void _delete(List<String> ids) {
    if (ids.isEmpty) return;
    mirror.deleteItems(ids);
    markChanged();
  }
}
