// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/session/session_store.dart';

import '../support/fakes.dart';

void main() {
  final s = StoredSession(
    serverUrl: Uri.parse('https://vault.example.org'),
    userId: testUserId,
    deviceId: testDeviceId,
    email: 'camille@example.org',
    refreshToken: 'r1',
    isInstanceOwner: true,
    displayName: 'Camille',
  );

  test(
    'stored under unfeudal.session.v1 with exactly its seven fields',
    () async {
      final kv = FakeSecureKv();
      await SessionStore(kv).save(s);
      expect(jsonDecode(kv.values['unfeudal.session.v1']!), {
        'serverUrl': 'https://vault.example.org',
        'userId': testUserId,
        'deviceId': testDeviceId,
        'email': 'camille@example.org',
        'refreshToken': 'r1',
        'isInstanceOwner': true,
        'displayName': 'Camille',
      });
      expect((await SessionStore(kv).load())!.toJson(), s.toJson());
    },
  );

  test('missing or unreadable means logged out', () async {
    final kv = FakeSecureKv();
    expect(await SessionStore(kv).load(), isNull);
    kv.values['unfeudal.session.v1'] = '{"userId": 3}';
    expect(await SessionStore(kv).load(), isNull);
  });

  test('refresh token rotation and clear', () async {
    final kv = FakeSecureKv();
    final store = SessionStore(kv);
    await store.save(s);
    await store.saveRefreshToken('r2');
    expect((await store.load())!.refreshToken, 'r2');
    await store.forgetRefreshToken();
    expect(
      ((await store.load())!.refreshToken, (await store.load())!.email),
      (null, s.email),
    );
    await store.clear();
    expect(kv.values, isEmpty);
  });
}
