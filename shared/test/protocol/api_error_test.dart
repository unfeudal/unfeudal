// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('every code has its wire name and status', () {
    expect(
      {for (final c in ApiErrorCode.values) c.wire: c.status},
      {
        'invalid_request': 400,
        'unauthorized': 401,
        'forbidden': 403,
        'not_found': 404,
        'conflict': 409,
        'payload_too_large': 413,
        'rate_limited': 429,
        'setup_done': 409,
        'feature_disabled': 404,
        'internal': 500,
      },
    );
    expect(ApiErrorCode.fromWire('rate_limited'), ApiErrorCode.rateLimited);
    expect(ApiErrorCode.fromWire('teapot'), isNull);
  });

  test('unknown code is kept as text; message defaults to empty', () {
    final b = ApiErrorBody.fromJson({'error': 'teapot'});
    expect((b.error, b.code, b.message), ('teapot', null, ''));
  });

  test('conflict body keeps item, reason and extra fields', () {
    final item = {
      'id': '6f1c2b9a-3d4e-4f50-8a61-7b8c9d0e1f20',
      'type': 'host',
      'scope': 'personal',
      'orgId': null,
      'folderId': null,
      'schemaVersion': 1,
      'revision': 4,
      'deleted': false,
      'meta': {
        'v': 1,
        'alg': 'xchacha20poly1305',
        'keyId': 'user',
        'nonce': b64(List.filled(24, 0)),
        'ct': b64(List.filled(16, 0)),
      },
      'secret': null,
    };
    final json = {
      'error': 'conflict',
      'message': 'Revision mismatch.',
      'item': item,
    };
    final b = ApiErrorBody.fromJson(json);
    expect((b.code, b.item!.revision), (ApiErrorCode.conflict, 4));
    expect(jsonEncode(b.toJson()), jsonEncode(json));
    final gone = {'error': 'conflict', 'message': 'Gone.', 'item': null};
    expect(jsonEncode(ApiErrorBody.fromJson(gone).toJson()), jsonEncode(gone));
    final lastOwner = {
      'orgs': ['Acme'],
      'error': 'conflict',
      'message': '',
      'reason': 'last_owner',
    };
    expect(
      jsonEncode(ApiErrorBody.fromJson(lastOwner).toJson()),
      jsonEncode(lastOwner),
    );
  });

  test('401 reasons; unknown or missing means session expired', () {
    expect(UnauthorizedReason.values.map((r) => r.wire), [
      'invalid_token',
      'device_revoked',
      'session_expired',
    ]);
    expect(
      UnauthorizedReason.fromWire('device_revoked'),
      UnauthorizedReason.deviceRevoked,
    );
    expect(
      UnauthorizedReason.fromWire('something_new'),
      UnauthorizedReason.sessionExpired,
    );
    expect(
      UnauthorizedReason.fromWire(null),
      UnauthorizedReason.sessionExpired,
    );
  });

  test('malformed error bodies throw FormatException', () {
    for (final bad in <Object?>[
      'x',
      {'message': 'm'},
      {'error': 1},
      {'error': 'conflict', 'item': 'x'},
      {'error': 'e', 'reason': 3},
    ]) {
      expect(
        () => ApiErrorBody.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });
}
