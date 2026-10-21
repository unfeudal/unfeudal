// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const u = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const d = '8c7b6a59-4e3d-4c2b-a190-8f7e6d5c4b3a';
const device = {
  'id': d,
  'name': 'Windows',
  'platform': 'windows',
  'createdAt': '2026-10-13T12:00:00.000Z',
  'lastSeenAt': '2026-10-14T08:00:00.000Z',
  'revokedAt': null,
  'current': true,
};

void main() {
  late Map<String, Object?> session;
  setUpAll(() async {
    final acc = await AccountCrypto(
      kdf: KdfParams.testing,
      kdfFloor: KdfParams.testing,
    ).create('correct horse');
    session = {
      'userId': u,
      'deviceId': d,
      'accessToken': 'a.b',
      'refreshToken': 'r',
      'bundle': acc.bundle.toJson(),
      'bundleVersion': 0,
      'isInstanceOwner': true,
    };
  });

  test('Session round-trips', () {
    final s = Session.fromJson(jsonDecode(jsonEncode(session)));
    expect((s.userId, s.bundleVersion, s.isInstanceOwner), (u, 0, true));
    expect(jsonEncode(s.toJson()), jsonEncode(session));
  });

  test('TokenPair round-trips', () {
    final t = TokenPair.fromJson({'accessToken': 'a.b', 'refreshToken': 'r'});
    expect(jsonEncode(t.toJson()), '{"accessToken":"a.b","refreshToken":"r"}');
  });

  test('Device round-trips', () {
    final dev = Device.fromJson(device);
    expect(
      (dev.platform, dev.revokedAt, dev.isCurrent),
      ('windows', null, true),
    );
    expect(jsonEncode(dev.toJson()), jsonEncode(device));
  });

  test('platforms list', () {
    expect(devicePlatforms, [
      'windows',
      'macos',
      'linux',
      'android',
      'ios',
      'other',
    ]);
  });

  test('malformed sessions throw FormatException', () {
    for (final over in [
      {'userId': 'u1'},
      {'bundleVersion': -1},
      {'isInstanceOwner': 'yes'},
      {'bundle': <String, Object?>{}},
      {'accessToken': null},
    ]) {
      expect(
        () => Session.fromJson({...session, ...over}),
        throwsFormatException,
        reason: '$over',
      );
    }
  });

  test('a device with an empty name throws FormatException', () {
    expect(
      () => Device.fromJson({...device, 'name': ''}),
      throwsFormatException,
    );
  });
}
