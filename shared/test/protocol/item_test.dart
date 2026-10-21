// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const id = '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20';
const org = '3c5e7a9b-1d2f-4e6a-8b0c-2d4f6a8c0e1a';
const folder = '7e9a1c3e-5f7b-4d9f-b1a3-c5e7a9b1d3f5';
const user = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const device = '8c7b6a59-4e3d-4c2b-a190-8f7e6d5c4b3a';
final env = {
  'v': 1,
  'alg': 'xchacha20poly1305',
  'keyId': 'user',
  'nonce': b64(List.filled(24, 0)),
  'ct': b64(List.filled(16, 0)),
};

Map<String, Object?> item([Map<String, Object?> over = const {}]) => {
  'id': id,
  'type': 'host',
  'scope': 'personal',
  'orgId': null,
  'folderId': null,
  'schemaVersion': 1,
  'revision': 3,
  'deleted': false,
  'meta': env,
  'secret': null,
  'createdAt': '2026-10-01T09:00:00.000Z',
  'updatedAt': '2026-10-13T12:00:00.000Z',
  'updatedBy': user,
  'updatedDevice': device,
  ...over,
};

void main() {
  test('server item round-trips in wire order, unknown fields first', () {
    final json = {'pinnedBy': 'future', ...item()};
    final i = Item.fromJson(json);
    expect(
      (i.kind, i.scope, i.revision, i.createdAt, i.updatedAt),
      (
        ItemKind.host,
        ItemScope.personal,
        3,
        DateTime.utc(2026, 10, 1, 9),
        DateTime.utc(2026, 10, 13, 12),
      ),
    );
    expect(jsonEncode(i.toJson()), jsonEncode(json));
  });

  test('client body without server fields round-trips', () {
    final json = item()
      ..remove('revision')
      ..remove('createdAt')
      ..remove('updatedAt')
      ..remove('updatedBy')
      ..remove('updatedDevice');
    expect(jsonEncode(Item.fromJson(json).toJson()), jsonEncode(json));
  });

  test('org item reads its org and folder', () {
    final o = Item.fromJson(
      item({'scope': 'org', 'orgId': org, 'folderId': folder}),
    );
    expect((o.scope, o.orgId, o.folderId), (ItemScope.org, org, folder));
  });

  test('tombstone round-trips with purged after deleted', () {
    final tomb = {
      for (final e in item({'deleted': true, 'meta': null}).entries) ...{
        e.key: e.value,
        if (e.key == 'deleted') 'purged': true,
      },
    };
    final t = Item.fromJson(tomb);
    expect(
      (t.purged, t.meta, t.createdAt),
      (true, null, DateTime.utc(2026, 10, 1, 9)),
    );
    // `purged` comes right after `deleted`.
    expect(jsonEncode(t.toJson()), jsonEncode(tomb));
    expect(Item.fromJson(item()).toJson().containsKey('purged'), isFalse);
  });

  test('unknown type is kept as ItemKind.unknown', () {
    final u = Item.fromJson(item({'type': 'futureThing'}));
    expect((u.type, u.kind), ('futureThing', ItemKind.unknown));
  });

  test('personal-only types', () {
    expect(
      ItemKind.values.map((k) => k.name),
      containsAll(['knownHost', 'hostBinding', 'memberPin', 'profile']),
    );
    expect(personalOnlyTypes, {
      'knownHost',
      'profile',
      'hostBinding',
      'memberPin',
    });
  });

  test('malformed items throw FormatException', () {
    final bad = <Map<String, Object?>>[
      item({'id': id.toUpperCase()}),
      item({'type': ''}),
      item({'type': 'x' * 65}),
      item({'scope': 'team'}),
      item({'scope': 'org'}),
      item({'orgId': org}),
      item({'folderId': 'f1'}),
      item({'schemaVersion': 0}),
      item({'revision': '3'}),
      item({'deleted': 'no'}),
      item({'purged': false}),
      item({'meta': null}),
      item({'secret': 'x'}),
      item({'createdAt': '2026-10-01T09:00:00Z'}),
      item({'updatedAt': '2026-10-13T12:00:00Z'}),
      item({'updatedBy': 'u1'}),
    ];
    for (final json in bad) {
      expect(() => Item.fromJson(json), throwsFormatException, reason: '$json');
    }
  });
}
