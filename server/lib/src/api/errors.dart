// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'app.dart';
import 'json.dart';

/// Answered as `{error, message, ...extra}` with the code's status.
class ApiError implements Exception {
  ApiError(this.code, this.message, {this.extra = const {}, this.retryAfter});

  final ApiErrorCode code;

  /// Never contains a submitted value.
  final String message;
  final Map<String, Object?> extra;

  /// Seconds, sent as `retry-after` on 429.
  final int? retryAfter;

  @override
  String toString() => 'ApiError(${code.wire}): $message';
}

/// ApiError → its JSON body and status; anything else → 500, logging only the path and the type.
Middleware errorMapper() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on ApiError catch (e) {
        return _respond(e);
      } catch (e) {
        depsOf(request).log.error('internal', {
          'path': request.url.path,
          'type': '${e.runtimeType}',
        });
        return _respond(ApiError(ApiErrorCode.internal, 'Internal error.'));
      }
    };

Response _respond(ApiError e) => jsonResponse(
  {'error': e.code.wire, 'message': e.message, ...e.extra},
  status: e.code.status,
  headers: {if (e.retryAfter != null) 'retry-after': '${e.retryAfter}'},
);
