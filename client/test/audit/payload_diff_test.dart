// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/audit/payload_diff.dart';

List<List<Object?>> shape(List<FieldChange> d) => [
  for (final c in d) [c.field, c.before, c.after],
];

void main() {
  test('changed, added and removed fields, by name; lists and maps by value; schemaVersion ignored', () {
    final d = diffPayloads(
      {
        'schemaVersion': 1,
        'name': 'prod-1',
        'port': 22,
        'tags': ['web'],
        'notes': 'x',
        'forwards': [
          {'localPort': 1},
        ],
      },
      {
        'schemaVersion': 2,
        'name': 'prod-web-1',
        'port': 22,
        'tags': ['web', 'nginx'],
        'user': 'deploy',
        'forwards': [
          {'localPort': 1},
        ],
      },
    );
    expect(shape(d), [
      ['name', 'prod-1', 'prod-web-1'],
      ['notes', 'x', null],
      [
        'tags',
        ['web'],
        ['web', 'nginx'],
      ],
      ['user', null, 'deploy'],
    ]);
  });

  test('a missing side and equal payloads', () {
    expect(diffPayloads({'name': 'a'}, {'name': 'a'}), isEmpty);
    expect(shape(diffPayloads(null, {'password': 'b'})), [
      ['password', null, 'b'],
    ]);
  });
}
