// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final good = <String, Object?>{
    'v': 1,
    'alg': 'xchacha20poly1305',
    'keyId': 'user',
    'nonce': b64(List.filled(24, 1)),
    'ct': b64(List.filled(16, 2)),
  };

  test('round-trips with unknown fields written first', () {
    final json = {
      'future': {'x': 1},
      ...good,
    };
    final e = Envelope.fromJson(json);
    expect(e.isSupported, isTrue);
    expect(e.extra, {
      'future': {'x': 1},
    });
    expect(jsonEncode(e.toJson()), jsonEncode(json));
  });

  test('a newer version or algorithm parses and is unsupported', () {
    final e = Envelope.fromJson({
      ...good,
      'v': 2,
      'alg': 'future-aead',
      'nonce': 'AAAA',
      'ct': 'AAAA',
    });
    expect(e.isSupported, isFalse);
    expect(e.toJson()['nonce'], 'AAAA');
  });

  test('malformed envelopes throw FormatException', () {
    final bad = <Object?>[
      'str',
      [1],
      {...good, 'v': '1'},
      Map.of(good)..remove('keyId'),
      {...good, 'keyId': 'a\u0000b'},
      {...good, 'nonce': b64(List.filled(12, 0))},
      {...good, 'ct': b64(List.filled(15, 0))},
      {...good, 'ct': '+/+/'},
      {...good, 'keyId': 'k' * 257},
    ];
    for (final json in bad) {
      expect(
        () => Envelope.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });

  test('key labels have their pinned text', () {
    const f = '11111111-1111-4111-8111-111111111111';
    expect(
      [
        KeyIds.master,
        KeyIds.recovery,
        KeyIds.userX25519,
        KeyIds.user,
        KeyIds.enroll,
        KeyIds.export,
        KeyIds.biometric,
      ],
      [
        'master',
        'recovery',
        'user-x25519',
        'user',
        'enroll',
        'export',
        'biometric',
      ],
    );
    expect(KeyIds.folder(f, 3, PayloadPart.secret), 'folder:$f:v3:secret');
    expect(
      KeyIds.sealed(KeyIds.folder(f, 1, PayloadPart.meta)),
      'sealed:folder:$f:v1:meta',
    );
  });

  test(
    'parseFolder reads folder labels and returns null for anything else',
    () {
      const f = '11111111-1111-4111-8111-111111111111';
      final p = KeyIds.parseFolder('folder:$f:v3:secret')!;
      expect((p.folderId, p.version, p.part), (f, 3, PayloadPart.secret));
      for (final s in [
        'user',
        'folder:$f:v0:meta',
        'folder:$f:v01:meta',
        'folder:$f:v1:other',
        'folder:NOT-A-UUID:v1:meta',
        'sealed:folder:$f:v1:meta',
      ]) {
        expect(KeyIds.parseFolder(s), isNull, reason: s);
      }
    },
  );

  test('crypto errors are typed exceptions', () {
    const all = <Exception>[
      WrongPassword(),
      DecryptionFailed(),
      UnsupportedEnvelope('x'),
      UnsupportedKdf('x'),
      WeakKdf(),
      WeakPassword(),
      InvalidRecoveryKey(),
      KeyLabelMismatch('x'),
    ];
    expect(all.map((e) => e.runtimeType).toSet().length, 8);
  });
}
