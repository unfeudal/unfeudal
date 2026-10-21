// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

final page = {'items': <Object?>[], 'cursor': 0, 'more': false};

final orgBlock = <String, Object?>{
  'orgCursor': 12,
  for (final list in [
    'orgs',
    'members',
    'teams',
    'acl',
    'folderTree',
    'wrappedKeys',
    'keyHistory',
    'keyRequests',
    'pendingRotations',
    'itemIds',
  ])
    list: <Object?>[],
};

void main() {
  test('a page without an org block reads as no org', () {
    final syncPage = SyncPage.fromJson(page);
    expect(syncPage.items, isEmpty);
    expect((syncPage.cursor, syncPage.hasMore, syncPage.org), (0, false, null));
  });

  test('a page with an org block reads it', () {
    final syncPage = SyncPage.fromJson({...page, 'org': orgBlock});
    expect(syncPage.org!.orgCursor, 12);
  });

  test('a malformed page is a FormatException', () {
    final malformed = {
      'negative cursor': {...page, 'cursor': -1},
      'missing more': {'items': <Object?>[], 'cursor': 0},
    };
    for (final MapEntry(key: reason, value: json) in malformed.entries) {
      expect(
        () => SyncPage.fromJson(json),
        throwsFormatException,
        reason: reason,
      );
    }
  });
}
