// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const h = '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20';
const i = '4a6c8e0a-2b4d-4f6a-8c0e-2a4c6e8a0c2e';
final fp = 'SHA256:${'A' * 43}';

void expectRoundTrip(
  Object Function(Object?) parse,
  Map<String, Object?> json,
) => expect(
  jsonEncode((parse(json) as Payload).toJson()),
  jsonEncode(json),
  reason: '$json',
);

void main() {
  test('each payload round-trips with unknown fields', () {
    expectRoundTrip(KnownHostMeta.fromJson, {
      'x': 1,
      'schemaVersion': 1,
      'hostItemId': h,
      'keyType': 'ssh-ed25519',
      'sha256Fingerprint': fp,
    });
    expectRoundTrip(ProfileMeta.fromJson, {
      'avatarSeed': 7,
      'schemaVersion': 1,
      'displayName': 'Alice',
      'prefs': {'themeMode': 'dark', 'futurePref': true},
    });
    expectRoundTrip(ProfileMeta.fromJson, {
      'schemaVersion': 1,
      'displayName': null,
    });
    expectRoundTrip(SnippetMeta.fromJson, {
      'color': 'blue',
      'schemaVersion': 1,
      'name': 'Disk',
      'command': ' df -h\n',
      'tags': ['ops'],
    });
    expectRoundTrip(HostBindingMeta.fromJson, {
      'x': 1,
      'schemaVersion': 1,
      'hostItemId': h,
      'identityId': i,
    });
    expectRoundTrip(MemberPinMeta.fromJson, {
      'x': 1,
      'schemaVersion': 1,
      'userId': i,
      'fingerprint': 'a' * 40,
      'verified': true,
    });
  });

  test('defaults: empty prefs not written, verified false when absent, command not trimmed', () {
    expect(
      ProfileMeta.fromJson({
        'schemaVersion': 1,
        'displayName': null,
        'prefs': <String, Object?>{},
      }).toJson().containsKey('prefs'),
      isFalse,
    );
    expect(
      MemberPinMeta.fromJson({
        'schemaVersion': 1,
        'userId': i,
        'fingerprint': 'a' * 40,
      }).verified,
      isFalse,
    );
    expect(
      SnippetMeta.fromJson({
        'schemaVersion': 1,
        'name': ' n ',
        'command': ' ls ',
        'tags': <String>[],
      }).command,
      ' ls ',
    );
    expect(syncedPrefKeys, [
      'themeMode',
      'terminalTheme',
      'loquetMode',
      'locale',
      'terminalFont',
      'terminalFontSize',
    ]);
  });

  test('malformed payloads throw FormatException', () {
    final bad = <(Object Function(Object?), Map<String, Object?>)>[
      (
        KnownHostMeta.fromJson,
        {
          'schemaVersion': 1,
          'hostItemId': h,
          'keyType': 'k',
          'sha256Fingerprint': 'SHA256:short',
        },
      ),
      (
        KnownHostMeta.fromJson,
        {
          'schemaVersion': 1,
          'hostItemId': 'h',
          'keyType': 'k',
          'sha256Fingerprint': fp,
        },
      ),
      (
        KnownHostMeta.fromJson,
        {
          'schemaVersion': 1,
          'hostItemId': h,
          'keyType': 'k' * 65,
          'sha256Fingerprint': fp,
        },
      ),
      (ProfileMeta.fromJson, {'schemaVersion': 1, 'displayName': 'd' * 65}),
      (
        ProfileMeta.fromJson,
        {
          'schemaVersion': 1,
          'displayName': null,
          'prefs': {for (var n = 0; n < 65; n++) 'k$n': n},
        },
      ),
      (
        SnippetMeta.fromJson,
        {'schemaVersion': 1, 'name': 'n' * 121, 'command': 'c', 'tags': []},
      ),
      (
        SnippetMeta.fromJson,
        {'schemaVersion': 1, 'name': 'n', 'command': '  ', 'tags': []},
      ),
      (
        SnippetMeta.fromJson,
        {'schemaVersion': 1, 'name': 'n', 'command': 'c' * 16385, 'tags': []},
      ),
      (
        HostBindingMeta.fromJson,
        {'schemaVersion': 1, 'hostItemId': h, 'identityId': 'x'},
      ),
      (
        MemberPinMeta.fromJson,
        {'schemaVersion': 1, 'userId': i, 'fingerprint': 'A' * 40},
      ),
      (
        MemberPinMeta.fromJson,
        {
          'schemaVersion': 1,
          'userId': i,
          'fingerprint': 'a' * 40,
          'verified': 'yes',
        },
      ),
    ];
    for (final (parse, json) in bad) {
      expect(() => parse(json), throwsFormatException, reason: '$json');
    }
  });
}
