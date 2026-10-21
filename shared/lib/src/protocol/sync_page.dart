// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'item.dart';
import 'org_block.dart';

/// One `GET /sync` response page.
class SyncPage {
  SyncPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
    this.org,
  });

  factory SyncPage.fromJson(Object? json) {
    final r = JsonReader(json, 'syncPage');
    final org = r.opt<Map<String, Object?>>('org');
    return SyncPage(
      items: [
        for (final item in r.list<Object>('items', max: 500))
          Item.fromJson(item),
      ],
      cursor: r.integer('cursor'),
      hasMore: r.flag('more'),
      org: org == null ? null : OrgBlock.fromJson(org),
    );
  }

  final List<Item> items;
  final int cursor;
  final bool hasMore;

  /// Present only when the org block changed since the request's orgCursor.
  final OrgBlock? org;
}
