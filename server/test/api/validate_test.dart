// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/validate.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/matchers.dart';

void main() {
  final bad = throwsApi(ApiErrorCode.invalidRequest);

  test(
    'normalizeEmail trims, lowercases, checks shape and 254 code points',
    () {
      expect(normalizeEmail('  Alice@Example.ORG '), 'alice@example.org');
      expect(normalizeEmail('${'a' * 240}@example.org'), hasLength(252));
      for (final v in <Object?>[
        'a',
        'a@b',
        '@b.c',
        'a b@c.d',
        null,
        7,
        '${'a' * 250}@b.co',
      ]) {
        expect(() => normalizeEmail(v), bad, reason: '$v');
      }
    },
  );

  test('reqString counts code points; reqKey32 needs 32 bytes', () {
    expect(reqString({'n': '😀' * 1024}, 'n'), hasLength(2048));
    for (final m in [
      <String, Object?>{},
      {'n': ''},
      {'n': 3},
      {'n': 'é' * 1025},
    ]) {
      expect(() => reqString(m, 'n'), bad, reason: '$m');
    }
    expect(() => reqString({'n': 'abcd'}, 'n', max: 3), bad);
    expect(reqKey32({'k': b64(List.filled(32, 1))}, 'k'), List.filled(32, 1));
    for (final v in [b64(List.filled(31, 1)), 'not base64!', 32, null]) {
      expect(() => reqKey32({'k': v}, 'k'), bad, reason: '$v');
    }
  });

  test('parseBundle checks the model and the KDF bounds', () async {
    final acc = await AccountCrypto(
      kdf: KdfParams.testing,
      kdfFloor: KdfParams.testing,
    ).create('correct horse');
    final raw = acc.bundle.toJson();
    expect(parseBundle(raw, kdfFloor: KdfParams.testing), same(raw));
    expect(
      () => parseBundle(raw),
      bad,
      reason: 'testing KDF refused in production',
    );
    final huge = {
      ...raw,
      'kdf': {'alg': 'argon2id', 'm': 1 << 20, 't': 3, 'p': 4},
    };
    expect(() => parseBundle(huge, kdfFloor: KdfParams.testing), bad);
    expect(
      () => parseBundle({...raw, 'salt': 'AAAA'}, kdfFloor: KdfParams.testing),
      bad,
    );
    expect(() => parseBundle('x', kdfFloor: KdfParams.testing), bad);
  });

  test('parseDevice trims, then 1 to 100 code points, no control char, known platform', () {
    final d = parseDevice({'name': '  Laptop  ', 'platform': 'linux'});
    expect((d.name, d.platform), ('Laptop', 'linux'));
    expect(
      parseDevice({'name': 'é' * 100, 'platform': 'other'}).name,
      hasLength(100),
    );
    for (final v in <Object?>[
      {'name': 'é' * 101, 'platform': 'linux'},
      {'name': '   ', 'platform': 'linux'},
      {'name': 'a\u0007b', 'platform': 'linux'},
      {'name': 'a', 'platform': 'beos'},
      {'name': 'a'},
      'x',
    ]) {
      expect(() => parseDevice(v), bad, reason: '$v');
    }
  });

  test('If-Match, UUIDs and locales', () {
    expect(
      [
        parseIfMatch('3'),
        parseIfMatch(' "12" '),
        parseIfMatch('0'),
        parseIfMatch('999999999999999'),
      ],
      [3, 12, 0, 999999999999999],
    );
    for (final v in [null, '', 'abc', '1234567890123456', '-1', 'W/"3"']) {
      expect(() => parseIfMatch(v), bad, reason: '$v');
    }
    expect(
      parseUuid('6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20'),
      '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20',
    );
    expect(() => parseUuid('6F1C2B9A-3D4E-4F50-8A61-7B8C9D0E1F20'), bad);
    expect((parseLocale('en'), parseLocale('fr')), ('en', 'fr'));
    for (final v in <Object?>['de', 'EN', 1, null]) {
      expect(() => parseLocale(v), bad, reason: '$v');
    }
  });

  test('requireBundleChangeOnly allows only the listed fields, unknown ones included', () {
    final stored = {
      'salt': 'a',
      'kdf': {'alg': 'argon2id', 'm': 1, 't': 1, 'p': 1},
      'publicKey': 'k',
      'future': {'x': 1},
    };
    requireBundleChangeOnly(stored, {...stored, 'salt': 'b'}, {'salt'});
    requireBundleChangeOnly(stored, {
      'future': {'x': 1},
      'publicKey': 'k',
      'kdf': {'p': 1, 't': 1, 'm': 1, 'alg': 'argon2id'},
      'salt': 'a',
    }, {});
    for (final changed in [
      {...stored, 'publicKey': 'other'},
      {...stored, 'extra': 1},
      Map.of(stored)..remove('future'),
      {
        ...stored,
        'future': {'x': 2},
      },
    ]) {
      expect(
        () => requireBundleChangeOnly(stored, changed, {'salt'}),
        bad,
        reason: '$changed',
      );
    }
  });
}
