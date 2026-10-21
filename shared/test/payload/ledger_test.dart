// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const hostId = '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20';
const userId = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';

void main() {
  final json = {
    'future': 1,
    'seq': {'$hostId/meta': 4, '$hostId/secret': 4},
    'hostPins': {
      hostId: {
        'schemaVersion': 1,
        'hostItemId': hostId,
        'keyType': 'ssh-ed25519',
        'sha256Fingerprint': 'SHA256:${'B' * 43}',
      },
    },
    'memberPins': {
      userId: {'fingerprint': 'a' * 40, 'verified': true},
    },
    'startupApprovals': {hostId: 'C' * 43 + '='},
  };

  test('round-trips; empty ledger has four empty maps', () {
    final l = Ledger.fromJson(json);
    expect(
      (
        l.seq['$hostId/meta'],
        l.hostPins[hostId]!.keyType,
        l.memberPins[userId]!.verified,
      ),
      (4, 'ssh-ed25519', true),
    );
    expect(jsonEncode(l.toJson()), jsonEncode(json));
    expect(Ledger.empty().toJson(), {
      'seq': <String, Object?>{},
      'hostPins': <String, Object?>{},
      'memberPins': <String, Object?>{},
      'startupApprovals': <String, Object?>{},
    });
  });

  test('ledger and keyring AADs', () {
    expect(utf8.decode(ledgerAad.bytes), 'local:ledger/meta/ledger/personal//');
    expect(
      utf8.decode(keyringAad.bytes),
      'local:keyring/meta/ledger/personal//',
    );
  });

  test('sealed with the userKey under keyId user', () async {
    final key = SymmetricCipher.newKey();
    final e = await PayloadCrypto.seal(
      ledgerAad,
      Ledger.fromJson(json).toJson(),
      key,
      keyId: KeyIds.user,
      seq: 1,
    );
    final back = Ledger.fromJson(
      (await PayloadCrypto.open(ledgerAad, e, key)).json,
    );
    expect(jsonEncode(back.toJson()), jsonEncode(json));
    await expectLater(
      PayloadCrypto.open(keyringAad, e, key),
      throwsA(isA<DecryptionFailed>()),
    );
  });

  test('malformed ledgers throw FormatException', () {
    for (final bad in [
      {
        ...json,
        'seq': {'$hostId/other': 1},
      },
      {
        ...json,
        'seq': {'h1/meta': 1},
      },
      {
        ...json,
        'seq': {'$hostId/meta': 0},
      },
      {
        ...json,
        'hostPins': {'h1': (json['hostPins'] as Map)[hostId]},
      },
      {
        ...json,
        'memberPins': {
          userId: {'fingerprint': 'x'},
        },
      },
      {
        ...json,
        'startupApprovals': {'h1': 'x'},
      },
      Map.of(json)..remove('seq'),
    ]) {
      expect(() => Ledger.fromJson(bad), throwsFormatException, reason: '$bad');
    }
  });

  test(
    'startupCommandHash is padded base64 of SHA-256 and parses back',
    () async {
      final hash = await startupCommandHash('abc');
      expect(hash, 'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=');
      expect(
        Ledger.fromJson({
          ...json,
          'startupApprovals': {hostId: hash},
        }).startupApprovals[hostId],
        hash,
      );
    },
  );
}
