// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const jump = '1b3d5f7a-9c1e-4a3b-9d5f-7a9c1e3b5d7f';

void main() {
  test('folder round-trips; jumpHostId written only when set', () {
    final json = {
      'icon': 'server',
      'schemaVersion': 1,
      'name': 'Prod',
      'defaults': {
        'shell': 'bash',
        'port': 22,
        'user': 'root',
        'identityId': null,
        'jumpHostId': jump,
      },
    };
    final f = FolderMeta.fromJson(json);
    expect(
      (f.name, f.defaults.port, f.defaults.jumpHostId),
      ('Prod', 22, jump),
    );
    expect(f.defaults.extra, {'shell': 'bash'});
    expect(jsonEncode(f.toJson()), jsonEncode(json));
    final plain = FolderMeta.fromJson({
      'schemaVersion': 1,
      'name': 'X',
      'defaults': {'port': null, 'user': null, 'identityId': null},
    });
    expect(plain.toJson()['defaults'], {
      'port': null,
      'user': null,
      'identityId': null,
    });
  });

  test('malformed folders throw FormatException', () {
    Map<String, Object?> folder(
      Map<String, Object?> defaults, [
      String name = 'X',
    ]) => {
      'schemaVersion': 1,
      'name': name,
      'defaults': {'port': null, 'user': null, 'identityId': null, ...defaults},
    };
    for (final json in [
      folder({}, ' '),
      folder({}, 'x' * 101),
      folder({'port': 0}),
      folder({'user': 'u' * 65}),
      folder({'identityId': 'i'}),
      folder({'jumpHostId': 'j'}),
      {'schemaVersion': 1, 'name': 'X'},
      {'schemaVersion': 1, 'name': 'X', 'defaults': <Object?>[]},
    ]) {
      expect(
        () => FolderMeta.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
