// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no toIso8601String( and no import of unfeudal_shared internals in lib/ or bin/', () {
    final files = [
      for (final d in ['lib', 'bin'])
        // bin/ arrives with the CLI.
        if (Directory(d).existsSync())
          ...Directory(d).listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('toIso8601String(')), reason: f.path);
      expect(
        text,
        isNot(contains('package:unfeudal_shared/src/')),
        reason: f.path,
      );
    }
  });
}
