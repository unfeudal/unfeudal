// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';

void main() {
  test('the image names the source that /api/info announces by default', () {
    final source = Config.load(const {
      'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
    }).sourceUrl.toString();
    final dockerfile = File('../Dockerfile').readAsStringSync();
    expect(dockerfile, contains('org.opencontainers.image.source="$source"'));
    expect(
      dockerfile,
      contains('org.opencontainers.image.licenses="AGPL-3.0-or-later"'),
    );
  });
}
