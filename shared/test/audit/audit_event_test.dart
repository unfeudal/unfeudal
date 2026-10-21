// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const userId = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';

Map<String, Object?> eventJson() => {
  'scope': 'user:$userId',
  'seq': 1,
  'ts': '2026-10-15T12:00:00.000Z',
  'actorUser': userId,
  'actorDevice': null,
  'ip': 'ip:0123456789abcdef0123456789abcdef',
  'action': 'device.added',
  'targetIds': [userId],
  'prevHash': '0' * 64,
  'hash': 'ab' * 32,
};

void main() {
  test('round trip: unknown fields first, ipAddress only when present', () {
    final json = {'future': 1, ...eventJson()};
    expect(jsonEncode(AuditEvent.fromJson(json).toJson()), jsonEncode(json));
    final withIp = AuditEvent.fromJson({
      ...eventJson(),
      'ipAddress': '203.0.113.7',
    });
    expect(
      (withIp.ipAddress, withIp.toJson()['ipAddress']),
      ('203.0.113.7', '203.0.113.7'),
    );
  });

  test('hashFields: every field but prevHash, hash and ipAddress; nulls kept, ts as sent', () {
    final e = AuditEvent.fromJson({
      'future': 1,
      ...eventJson(),
      'ipAddress': '203.0.113.7',
    });
    expect(e.hashFields().keys.toSet(), {
      'future',
      'scope',
      'seq',
      'ts',
      'actorUser',
      'actorDevice',
      'ip',
      'action',
      'targetIds',
    });
    expect(
      (e.hashFields()['actorDevice'], e.hashFields()['ts']),
      (null, '2026-10-15T12:00:00.000Z'),
    );
  });

  test('malformed events are FormatException', () {
    for (final bad in [
      {...eventJson(), 'seq': 0},
      {
        ...eventJson(),
        'targetIds': [1],
      },
      {...eventJson()}..remove('hash'),
      {...eventJson(), 'ts': '2026-10-15'},
      {...eventJson(), 'action': ''},
      'event',
    ]) {
      expect(
        () => AuditEvent.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('cursor: base64url of {t, s, q}; malformed is FormatException', () {
    final c = const AuditCursor(
      t: '2026-10-15T12:00:00.000Z',
      s: 'instance',
      q: 7,
    );
    expect(jsonDecode(utf8.decode(unb64(c.encode()))), {
      't': '2026-10-15T12:00:00.000Z',
      's': 'instance',
      'q': 7,
    });
    final d = AuditCursor.decode(c.encode());
    expect((d.t, d.s, d.q), (c.t, c.s, c.q));
    for (final bad in [
      '',
      '!!',
      b64(utf8.encode('[]')),
      b64(utf8.encode('{"t":"x","s":"instance","q":1}')),
      b64(
        utf8.encode('{"t":"2026-10-15T12:00:00.000Z","s":"instance","q":-1}'),
      ),
      b64(utf8.encode('{"t":"2026-10-15T12:00:00.000Z","s":"","q":1}')),
    ]) {
      expect(() => AuditCursor.decode(bad), throwsFormatException, reason: bad);
    }
  });

  test('effectiveRetention: no org value gives the server one, server 0 gives the org one, else the smaller', () {
    expect(
      [
        effectiveRetention(365, null),
        effectiveRetention(0, 90),
        effectiveRetention(365, 90),
        effectiveRetention(30, 90),
        effectiveRetention(0, null),
      ],
      [365, 90, 90, 30, 0],
    );
  });

  test('a forward target carries its port and reads back', () {
    expect(forwardTarget(5432), 'forward:5432');
    expect(forwardPortOf(forwardTarget(5432)), '5432');
  });

  test('an id that is not a forward target has no port', () {
    expect(forwardPortOf(userId), isNull);
  });
}
