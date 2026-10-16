// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/errors.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

Matcher throwsApi(ApiErrorCode code) =>
    throwsA(isA<ApiError>().having((e) => e.code, 'code', code));
