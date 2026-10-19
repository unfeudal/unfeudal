// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

final full = {
  'api': [1],
  'minClient': '0.2.0',
  'latestClient': '0.3.0',
  'capabilities': ['mascot', 'sync'],
  'server': '0.3.1',
  'instanceEpoch': 'q83vEjRWeJCrze8SNFZ4kA',
  'source': 'https://example.org/src',
  'trashDays': 30,
};
ApiInfo info([Map<String, Object?> over = const {}]) =>
    ApiInfo.fromJson({...full, ...over});

void main() {
  test('versions are X.Y.Z compared numerically', () {
    expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
    expect(compareVersions('1.2.3', '1.2.3'), 0);
    expect(canonicalVersion('01.2.3'), '1.2.3');
    for (final s in [
      '1.2',
      '1.2.3-beta',
      '1.2.3+4',
      'v1.2.3',
      ' 1.2.3',
      '1.2.x',
      '1.2.${'3' * 30}',
      '',
    ]) {
      expect(() => canonicalVersion(s), throwsFormatException, reason: s);
    }
  });

  test('ApiInfo full and public forms round-trip; has()', () {
    expect(jsonEncode(info().toJson()), jsonEncode(full));
    final public = {
      'motd': 'kept',
      'api': [1],
      'minClient': '0.2.0',
      'latestClient': '0.3.0',
      'capabilities': ['sync'],
    };
    final p = ApiInfo.fromJson(public);
    expect(
      (p.server, p.instanceEpoch, p.trashDays, p.has('sync'), p.has('mascot')),
      (null, null, null, true, false),
    );
    expect(jsonEncode(p.toJson()), jsonEncode(public));
  });

  test('malformed ApiInfo throws FormatException', () {
    for (final over in [
      {
        'api': ['1'],
      },
      {'minClient': '1.0'},
      {'latestClient': null},
      {'capabilities': 'sync'},
      {'server': '0.3'},
      {'instanceEpoch': 'short'},
      {'instanceEpoch': '${'A' * 21}+'},
      {'trashDays': -1},
      {'source': 7},
    ]) {
      expect(() => info(over), throwsFormatException, reason: '$over');
    }
  });

  test('negotiate: full, client-too-old, no-common-api', () {
    final ok = negotiate('0.2.0', [1], info());
    expect((ok.mode, ok.api, ok.reason), (CompatMode.full, 1, null));
    final behind = negotiate('0.1.9', [1], info());
    expect(
      (behind.mode, behind.api, behind.reason),
      (CompatMode.readOnly, 1, 'client-too-old'),
    );
    final none = negotiate('9.0.0', [2], info());
    expect(
      (none.mode, none.api, none.reason),
      (CompatMode.readOnly, null, 'no-common-api'),
    );
    expect(
      negotiate(
        '0.2.0',
        [1, 2],
        info({
          'api': [1, 2, 3],
        }),
      ).api,
      2,
    );
  });
}
