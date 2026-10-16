// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/json.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/matchers.dart';

Request post(
  Stream<List<int>> body, [
  Map<String, String> headers = const {},
]) => Request('POST', Uri.parse('http://x/'), body: body, headers: headers);

void main() {
  const mib = 1 << 20;

  test('a body over 1 MiB is 413, declared or streamed', () async {
    await expectLater(
      readJson(
        post(Stream.value(utf8.encode('{}')), {'content-length': '${mib + 1}'}),
      ),
      throwsApi(ApiErrorCode.payloadTooLarge),
    );
    final chunks = Stream.fromIterable([
      utf8.encode('{"a":"'),
      List.filled(mib, 0x61),
      utf8.encode('"}'),
    ]);
    await expectLater(
      readJson(post(chunks)),
      throwsApi(ApiErrorCode.payloadTooLarge),
    );
  });

  test('exactly 1 MiB is read', () async {
    final text = '{"a":"${'x' * (mib - 8)}"}';
    expect(utf8.encode(text).length, mib);
    expect(
      (await readJson(post(Stream.value(utf8.encode(text)))))['a'],
      hasLength(mib - 8),
    );
  });

  test('not JSON, not UTF-8 or not an object is 400', () async {
    for (final bytes in [
      utf8.encode('{'),
      utf8.encode('[1]'),
      utf8.encode('"x"'),
      [0xff, 0xfe],
      <int>[],
    ]) {
      await expectLater(
        readJson(post(Stream.value(bytes))),
        throwsApi(ApiErrorCode.invalidRequest),
        reason: '$bytes',
      );
    }
  });

  test('jsonResponse and noContent', () async {
    final r = jsonResponse({'a': 1}, status: 201, headers: {'x-y': 'z'});
    expect(
      (r.statusCode, r.headers['content-type'], r.headers['x-y']),
      (201, 'application/json; charset=utf-8', 'z'),
    );
    expect(await r.readAsString(), '{"a":1}');
    expect(noContent().statusCode, 204);
  });
}
