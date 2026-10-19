// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/log/logger.dart';

void main() {
  test('redact hides secret keys and long base64 values, keeps UUIDs', () {
    const uuid = '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20';
    final out = redact({
      'refreshToken': 'r',
      'authKey': 'a',
      'Password': 'p',
      'bundle': <String, Object?>{},
      'publicKey': 'k',
      'ct': 'c',
      'cts': 'kept',
      'nonce': 'n',
      'recoveryAuthKey': 'x',
      'cookie': 'c',
      'Authorization': 'Bearer x',
      'envelope': <String, Object?>{},
      'privateKeyPem': 'p',
      'id': uuid,
      'path': '/api/v1/devices/$uuid',
      'blob': 'A' * 32,
      'short': 'A' * 31,
      'list': ['B' * 40, uuid],
      'nested': {'secret': 1, 'ok': 2},
      'n': 3,
    }) as Map<String, Object?>;
    for (final k in [
      'refreshToken',
      'authKey',
      'Password',
      'bundle',
      'publicKey',
      'ct',
      'nonce',
      'recoveryAuthKey',
      'cookie',
      'Authorization',
      'envelope',
      'privateKeyPem',
      'blob',
    ]) {
      expect(out[k], '[redacted]', reason: k);
    }
    expect(
      (out['cts'], out['id'], out['path'], out['short'], out['n']),
      ('kept', uuid, '/api/v1/devices/$uuid', 'A' * 31, 3),
    );
    expect(out['list'], ['[redacted]', uuid]);
    expect(out['nested'], {'secret': '[redacted]', 'ok': 2});
  });

  test(
    'levels filter lines; request lines carry exactly the listed fields',
    () {
      final lines = <String>[];
      final log = Logger(LogLevel.info, lines.add);
      log.request(
        method: 'GET',
        path: '/healthz',
        status: 200,
        ms: 1,
        ip: '127.0.0.1',
      );
      log.request(
        method: 'PUT',
        path: '/api/v1/items/x',
        status: 409,
        ms: 12,
        ip: '198.51.100.4',
      );
      log.info('started', {'port': 8080, 'setupToken': 'ABCD'});
      log.warn('slow');
      Logger(LogLevel.error, lines.add).warn('hidden');
      expect(lines.map(jsonDecode).toList(), [
        {
          'method': 'PUT',
          'path': '/api/v1/items/x',
          'status': 409,
          'ms': 12,
          'ip': '198.51.100.4',
        },
        {
          'level': 'info',
          'msg': 'started',
          'port': 8080,
          'setupToken': '[redacted]',
        },
        {'level': 'warn', 'msg': 'slow'},
      ]);
      final debug = <String>[];
      Logger(
        LogLevel.debug,
        debug.add,
      ).request(method: 'GET', path: '/healthz', status: 200, ms: 1, ip: '::1');
      expect(debug, hasLength(1));
    },
  );
}
