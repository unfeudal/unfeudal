// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'item.dart';

enum ApiErrorCode {
  invalidRequest('invalid_request', 400),
  unauthorized('unauthorized', 401),
  forbidden('forbidden', 403),
  notFound('not_found', 404),
  conflict('conflict', 409),
  payloadTooLarge('payload_too_large', 413),
  rateLimited('rate_limited', 429),
  setupDone('setup_done', 409),
  featureDisabled('feature_disabled', 404),
  internal('internal', 500);

  const ApiErrorCode(this.wire, this.status);

  final String wire;
  final int status;

  /// Null for a code this version does not know.
  static ApiErrorCode? fromWire(String wire) =>
      values.where((c) => c.wire == wire).firstOrNull;
}

enum UnauthorizedReason {
  invalidToken('invalid_token'),
  deviceRevoked('device_revoked'),
  sessionExpired('session_expired');

  const UnauthorizedReason(this.wire);

  final String wire;
}

/// `{error, message, item?, reason?, ...extra}`. An unknown [error] is kept
/// as text.
class ApiErrorBody {
  ApiErrorBody({
    required this.error,
    this.message = '',
    this.item,
    this.reason,
    this.extra = const {},
  });

  factory ApiErrorBody.fromJson(Object? json) {
    final r = JsonReader(json, 'error');
    final item = r.opt<Object>('item');
    return ApiErrorBody(
      error: r.text('error', max: 64),
      message: r.optText('message', max: 1024) ?? '',
      item: item == null ? null : Item.fromJson(item),
      reason: r.optText('reason', max: 64),
      extra: r.extra(const {'error', 'message', 'item', 'reason'}),
    );
  }

  final String error;
  final String message;
  final Item? item;
  final String? reason;
  final Map<String, Object?> extra;
}
