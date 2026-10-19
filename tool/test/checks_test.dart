// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_tool/checks.dart';

void main() {
  test('spdxProblems: AGPL under server/, Apache elsewhere; tool caches, builds and missing natives skipped', () {
    final d = Directory.systemTemp.createTempSync('uf_spdx_');
    void w(String path, String text) => File('${d.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    const agpl = '// SPDX-License-Identifier: AGPL-3.0-or-later\n';
    const apache = '// SPDX-License-Identifier: Apache-2.0\n';
    w('server/lib/a.dart', '${agpl}void a() {}\n');
    w('server/test/b.dart', '${apache}void b() {}\n');
    w('shared/lib/c.dart', 'void c() {}\n');
    w('client/.dart_tool/x.dart', 'void x() {}\n');
    w('client/build/y.dart', 'void y() {}\n');
    w('tool/bin/z.dart', '${apache}void main() {}\n');
    w('client/macos/Runner/BiometricVault.swift', '${apache}import Cocoa\n');
    w(
      'client/windows/runner/biometric_vault.cpp',
      '#include "biometric_vault.h"\n',
    );
    expect(spdxProblems(d), [
      'client/windows/runner/biometric_vault.cpp',
      'server/test/b.dart',
      'shared/lib/c.dart',
    ]);
  });

  test('changelogSection returns the notes of one version', () {
    const text =
        '# Changelog\n\n## [Unreleased]\n\n## [0.2.0] - 2026-11-02\n### Added\n- Export.\n\n## [0.1.0] - 2026-10-01\n- First.\n';
    expect(changelogSection(text, '0.2.0'), '### Added\n- Export.');
    expect(changelogSection(text, '9.9.9'), isNull);
  });
}
