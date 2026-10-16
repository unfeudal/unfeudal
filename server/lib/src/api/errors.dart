// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

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
