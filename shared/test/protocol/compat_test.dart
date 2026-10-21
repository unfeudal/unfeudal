// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

ApiInfo info({List<int> api = const [1]}) => ApiInfo(
  api: api,
  minClient: '0.2.0',
  latestClient: '0.3.0',
  capabilities: const ['sync'],
);

void main() {
  test('negotiate: a recent enough client gets full mode', () {
    final compat = negotiate('0.2.0', [1], info());
    expect(
      (compat.mode, compat.api, compat.reason),
      (CompatMode.full, 1, null),
    );
  });

  test('negotiate: a client below minClient is read-only', () {
    final compat = negotiate('0.1.9', [1], info());
    expect(
      (compat.mode, compat.api, compat.reason),
      (CompatMode.readOnly, 1, CompatReason.clientTooOld),
    );
  });

  test('negotiate: no common API is read-only without an API', () {
    final compat = negotiate('9.0.0', [2], info());
    expect(
      (compat.mode, compat.api, compat.reason),
      (CompatMode.readOnly, null, CompatReason.noCommonApi),
    );
  });

  test('negotiate: picks the highest common API', () {
    expect(negotiate('0.2.0', [1, 2], info(api: [1, 2, 3])).api, 2);
  });
}
