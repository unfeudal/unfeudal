// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/items/item_write.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/matchers.dart';

Map<String, Object?> load(Directory dir, String name) =>
    jsonDecode(File('${dir.path}/$name.json').readAsStringSync())
        as Map<String, Object?>;

void main() {
  final sets = Directory('../shared/test/fixtures')
      .listSync()
      .whereType<Directory>()
      .toList();

  test('the server accepts the items every release fixture set writes, unknown fields kept', () {
    expect(sets, isNotEmpty);
    for (final dir in sets) {
      final host = load(dir, 'item_host');
      final parsed = parseItemInput(host['id']! as String, host);
      expect(
        (parsed.type, parsed.extra['pinnedBy']),
        ('host', 'future-protocol-field'),
        reason: dir.path,
      );
      final unknown = load(dir, 'item_unknown_type');
      expect(
        parseItemInput(unknown['id']! as String, unknown).type,
        'futureThing',
        reason: dir.path,
      );
      final tomb = load(dir, 'item_tombstone');
      expect(
        () => parseItemInput(tomb['id']! as String, tomb),
        throwsApi(ApiErrorCode.invalidRequest),
        reason: 'a client never writes a tombstone (${dir.path})',
      );
    }
  });
}
