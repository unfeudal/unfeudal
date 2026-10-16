// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  const pub =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxOEp1uVUhGNsWGbwW5tYcyK7uLwHRTkzpYJb9zw9Rd deploy@unfeudal';

  test('meta and secret round-trip with unknown fields', () {
    final meta = {
      'createdWith': 'unfeudal',
      'schemaVersion': 1,
      'name': 'deploy',
      'kind': 'privateKey',
      'publicKey': pub,
    };
    expect(jsonEncode(IdentityMeta.fromJson(meta).toJson()), jsonEncode(meta));
    final secret = {
      'schemaVersion': 1,
      'kind': 'privateKey',
      'privateKeyPem': '-----BEGIN OPENSSH PRIVATE KEY-----\nx\n-----END OPENSSH PRIVATE KEY-----\n',
      'passphrase': 'pp',
      'password': null,
    };
    final s = IdentitySecret.fromJson(secret);
    expect((s.kind, s.passphrase), (IdentityKind.privateKey, 'pp'));
    expect(jsonEncode(s.toJson()), jsonEncode(secret));
    final pw = IdentitySecret.fromJson({
      'schemaVersion': 1,
      'kind': 'password',
      'privateKeyPem': null,
      'passphrase': null,
      'password': 'hunter22',
    });
    expect(pw.password, 'hunter22');
  });

  test('kind needs its secret; limits and shapes are enforced', () {
    final bad = <(Object Function(Object?), Map<String, Object?>)>[
      (
        IdentitySecret.fromJson,
        {
          'schemaVersion': 1,
          'kind': 'privateKey',
          'privateKeyPem': null,
          'passphrase': null,
          'password': null,
        },
      ),
      (
        IdentitySecret.fromJson,
        {
          'schemaVersion': 1,
          'kind': 'password',
          'privateKeyPem': null,
          'passphrase': null,
          'password': null,
        },
      ),
      (
        IdentitySecret.fromJson,
        {
          'schemaVersion': 1,
          'kind': 'password',
          'privateKeyPem': null,
          'passphrase': null,
          'password': 'p' * 1025,
        },
      ),
      (
        IdentitySecret.fromJson,
        {
          'schemaVersion': 1,
          'kind': 'privateKey',
          'privateKeyPem': 'k' * 16385,
          'passphrase': null,
          'password': null,
        },
      ),
      (
        IdentityMeta.fromJson,
        {'schemaVersion': 1, 'name': 'x', 'kind': 'token', 'publicKey': null},
      ),
      (
        IdentityMeta.fromJson,
        {
          'schemaVersion': 1,
          'name': ' ',
          'kind': 'password',
          'publicKey': null,
        },
      ),
      (
        IdentityMeta.fromJson,
        {
          'schemaVersion': 1,
          'name': 'x',
          'kind': 'privateKey',
          'publicKey': 'one-word',
        },
      ),
      (
        IdentityMeta.fromJson,
        {
          'schemaVersion': 1,
          'name': 'x',
          'kind': 'privateKey',
          'publicKey': '$pub\nssh-rsa AAAA',
        },
      ),
    ];
    for (final (parse, json) in bad) {
      expect(() => parse(json), throwsFormatException, reason: '$json');
    }
  });
}
