// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'errors.dart';

const maxBody = 1 << 20;

/// The body as a JSON object. Over 1 MiB (declared or streamed) gives a 413,
/// anything else malformed gives a 400.
Future<Map<String, Object?>> readJson(Request request) async {
  final declared = request.contentLength;
  if (declared != null && declared > maxBody) {
    throw ApiError(ApiErrorCode.payloadTooLarge, 'Body over 1 MiB.');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBody) {
      throw ApiError(ApiErrorCode.payloadTooLarge, 'Body over 1 MiB.');
    }
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes.takeBytes()));
  } on FormatException {
    throw ApiError(ApiErrorCode.invalidRequest, 'Body is not valid JSON.');
  }
  if (json is! Map<String, Object?>) {
    throw ApiError(ApiErrorCode.invalidRequest, 'Body must be a JSON object.');
  }
  return json;
}

Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => jsonTextResponse(jsonEncode(body), status: status, headers: headers);

/// [json] is already encoded.
Response jsonTextResponse(
  String json, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: json,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

Response noContent() => Response(204);
