// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

const _agpl = '// SPDX-License-Identifier: AGPL-3.0-or-later';
const _apache = '// SPDX-License-Identifier: Apache-2.0';

/// Native sources this project writes; the runner files `flutter create` generated are not its own.
const _natives = [
  'client/macos/Runner/BiometricVault.swift',
  'client/windows/runner/biometric_vault.h',
  'client/windows/runner/biometric_vault.cpp',
];

/// Sorted relative paths of the sources whose first line is not their SPDX header.
List<String> spdxProblems(Directory root) {
  String relative(File f) =>
      f.path.substring(root.path.length + 1).replaceAll(r'\', '/');
  final files = [
    for (final package in ['shared', 'server', 'client', 'tool'])
      if (Directory('${root.path}/$package').existsSync())
        for (final f in Directory(
          '${root.path}/$package',
        ).listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !RegExp(r'[/\\](\.dart_tool|build|ephemeral)[/\\]')
                  .hasMatch(f.path))
            relative(f),
    for (final path in _natives)
      if (File('${root.path}/$path').existsSync()) path,
  ];
  return [
    for (final path in files)
      if (!File('${root.path}/$path')
          .readAsStringSync()
          .startsWith(path.startsWith('server/') ? _agpl : _apache))
        path,
  ]..sort();
}

/// The notes under `## [<version>] - …`, trimmed; null when the changelog has no such section.
String? changelogSection(String text, String version) {
  final start = text.indexOf('## [$version] - ');
  if (start < 0) return null;
  final body = text.indexOf('\n', start);
  if (body < 0) return '';
  final end = text.indexOf('\n## [', body);
  return text.substring(body, end < 0 ? text.length : end).trim();
}
