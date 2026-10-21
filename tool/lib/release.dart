// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

final _semver = RegExp(r'^\d+\.\d+\.\d+$');
final _pubspecVersion = RegExp(r'^version: (\S+)$', multiLine: true);
const _serverVersionFile = 'server/lib/src/version.dart';
const _clientVersionFile = 'client/lib/src/version.dart';

/// Releases [package] (`server` or `client`) at [level] (`patch`, `minor`, `major` or `X.Y.Z`); returns its
/// released version. A client release also releases a server patch announcing it.
String bump(
  Directory root,
  String package,
  String level, {
  required DateTime date,
}) {
  if (package != 'server' && package != 'client') {
    throw ArgumentError.value(package, 'package', 'server or client');
  }
  final version = _nextVersion(_currentVersion(root, package), level);
  _release(root, package, version, date: date);
  if (package == 'server') return version;
  final serverPatch = _nextVersion(_currentVersion(root, 'server'), 'patch');
  _release(
    root,
    'server',
    serverPatch,
    date: date,
    note: '### Changed\n- Announces client $version.\n',
  );
  return version;
}

/// What stops [tag] from being released: versions, constants, changelog section and fixtures must all match it.
List<String> checkTag(Directory root, String tag) {
  final match = RegExp(r'^(server|client)-v(\d+\.\d+\.\d+)$').firstMatch(tag);
  if (match == null) return ['tag $tag is not server-vX.Y.Z or client-vX.Y.Z'];
  final (package, version) = (match[1]!, match[2]!);
  String read(String path) => File('${root.path}/$path').readAsStringSync();
  final problems = <String>[];
  if (_pubspecVersion.firstMatch(read('$package/pubspec.yaml'))?[1] !=
      version) {
    problems.add('$package/pubspec.yaml version is not $version');
  }
  final constants = package == 'server'
      ? [(_serverVersionFile, 'serverVersion')]
      : [
          (_clientVersionFile, 'clientVersion'),
          (_serverVersionFile, 'latestClientVersion'),
        ];
  for (final (file, name) in constants) {
    if (!read(file).contains("const $name = '$version';")) {
      problems.add('$file $name is not $version');
    }
  }
  if (package == 'client' &&
      read(_clientVersionFile).contains('firstPublicRelease = null')) {
    problems.add('$_clientVersionFile firstPublicRelease is not set');
  }
  if (!read('$package/CHANGELOG.md').contains('## [$version] - ')) {
    problems.add('$package/CHANGELOG.md has no [$version] section');
  }
  if (!Directory('${root.path}/shared/test/fixtures/v$version').existsSync()) {
    problems.add('no fixtures v$version');
  }
  return problems;
}

// The pubspec version without its `+build` part.
String _currentVersion(Directory root, String package) => _pubspecVersion
    .firstMatch(
      File('${root.path}/$package/pubspec.yaml').readAsStringSync(),
    )![1]!
    .split('+')
    .first;

String _nextVersion(String current, String level) {
  final [major, minor, patch] = current.split('.').map(int.parse).toList();
  return switch (level) {
    'patch' => '$major.$minor.${patch + 1}',
    'minor' => '$major.${minor + 1}.0',
    'major' => '${major + 1}.0.0',
    _ when _semver.hasMatch(level) => level,
    _ => throw FormatException(
      'version $level is not patch, minor, major or X.Y.Z',
    ),
  };
}

void _release(
  Directory root,
  String package,
  String version, {
  required DateTime date,
  String? note,
}) {
  final day = date.toIso8601String().substring(0, 10);
  void edit(String path, String Function(String text) change) {
    final file = File('${root.path}/$path');
    file.writeAsStringSync(change(file.readAsStringSync()));
  }

  String constant(String text, String name, String value) => text.replaceFirst(
    RegExp("const $name = '[^']*';"),
    "const $name = '$value';",
  );

  edit(
    '$package/pubspec.yaml',
    (t) => t.replaceFirst(_pubspecVersion, 'version: $version'),
  );
  if (package == 'server') {
    edit(_serverVersionFile, (t) => constant(t, 'serverVersion', version));
  } else {
    edit(
      _clientVersionFile,
      (t) => constant(t, 'clientVersion', version).replaceFirst(
        'const String? firstPublicRelease = null;',
        "const String? firstPublicRelease = '$day';",
      ),
    );
    edit(
      _serverVersionFile,
      (t) => constant(t, 'latestClientVersion', version),
    );
  }
  edit('$package/CHANGELOG.md', (t) {
    final header = '## [$version] - $day';
    var text = t.replaceFirst('## [Unreleased]', '## [Unreleased]\n\n$header');
    if (note != null) {
      final next = text.indexOf('\n## [', text.indexOf(header));
      text = next < 0
          ? '${text.endsWith('\n') ? text : '$text\n'}$note'
          : '${text.substring(0, next)}$note${text.substring(next)}';
    }
    return text;
  });
  _copyFixtures(root, version);
}

// The newest `shared/test/fixtures/v*` becomes `v<version>`: the formats this release reads.
void _copyFixtures(Directory root, String version) {
  final fixtures = Directory('${root.path}/shared/test/fixtures');
  final target = Directory('${fixtures.path}/v$version');
  if (target.existsSync()) return;
  String sortKey(Directory d) => d.path
      .split(RegExp(r'[/\\]'))
      .last
      .substring(1)
      .split('.')
      .map((n) => n.padLeft(6, '0'))
      .join('.');

  final versions =
      fixtures
          .listSync()
          .whereType<Directory>()
          .where((d) => RegExp(r'[/\\]v[\d.]+$').hasMatch(d.path))
          .toList()
        ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
  if (versions.isEmpty) return;
  for (final f in versions.last.listSync(recursive: true).whereType<File>()) {
    final relative = f.path.substring(versions.last.path.length + 1);
    File('${target.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(f.readAsBytesSync());
  }
}
