// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/errors.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

Matcher throwsApi(ApiErrorCode code) =>
    throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

// SQLITE_CONSTRAINT is result code 19; PostgreSQL integrity violations are SQLSTATE class 23.
final Matcher throwsConstraintViolation = throwsA(
  anyOf(
    isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 19),
    isA<ServerException>().having((e) => e.code, 'code', startsWith('23')),
  ),
);
