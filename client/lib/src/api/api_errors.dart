// SPDX-License-Identifier: Apache-2.0
part of 'api_client.dart';

/// A non-2xx answer. [code] keeps an unknown wire code; [known] is null for it.
class ApiException implements Exception {
  ApiException(
    this.code,
    this.status, {
    this.message = '',
    this.reason,
    this.item,
    this.orgs,
    this.retryAfter,
  });

  final String code;
  final int status;
  final String message;
  final String? reason;
  final Item? item;
  final List<String>? orgs;
  final Duration? retryAfter;

  ApiErrorCode? get known => ApiErrorCode.fromWire(code);
  ConflictReason? get conflictReason => ConflictReason.fromWire(reason);
  UnauthorizedReason? get unauthorizedReason =>
      UnauthorizedReason.fromWire(reason);

  @override
  String toString() =>
      'ApiException($status $code${reason == null ? '' : ' $reason'})';
}

/// The server could not be reached: socket, TLS, timeout.
class NetworkException implements Exception {
  NetworkException(this.cause);
  final Object cause;

  @override
  String toString() => 'NetworkException($cause)';
}

/// A write refused locally because the client is read-only toward this server.
class ReadOnlyException implements Exception {
  const ReadOnlyException();
}

typedef DeviceInput = ({String name, String platform});

// 2xx: the JSON body, null when empty. Else an ApiException; a body that is not JSON is a FormatException.
Object? _decode(http.Response res) {
  if (res.statusCode >= 200 && res.statusCode < 300) {
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }
  final error = ApiErrorBody.fromJson(jsonDecode(res.body));
  final after = int.tryParse(res.headers['retry-after'] ?? '');
  return throw ApiException(
    error.error,
    res.statusCode,
    message: error.message,
    reason: error.reason,
    item: error.item,
    orgs: (error.extra['orgs'] as List<Object?>?)?.cast<String>(),
    retryAfter: after == null ? null : Duration(seconds: after),
  );
}

String? _reasonOf(http.Response res) {
  try {
    return ApiErrorBody.fromJson(jsonDecode(res.body)).reason;
  } on FormatException {
    return null;
  }
}
