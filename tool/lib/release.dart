// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

final _semver = RegExp(r'^\d+\.\d+\.\d+$');
final _pubspecVersion = RegExp(r'^version: (\S+)$', multiLine: true);

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
  final version = _resolve(_current(root, package), level);
  _release(root, package, version, date: date);
  if (package == 'server') return version;
  final serverPatch = _resolve(_current(root, 'server'), 'patch');
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
  final m = RegExp(r'^(server|client)-v(\d+\.\d+\.\d+)$').firstMatch(tag);
  if (m == null) return ['tag $tag is not server-vX.Y.Z or client-vX.Y.Z'];
  final (pkg, v) = (m[1]!, m[2]!);
  String read(String path) => File('${root.path}/$path').readAsStringSync();
  final problems = <String>[];
  if (!RegExp(
    '^version: ${RegExp.escape(v)}\$',
    multiLine: true,
  ).hasMatch(read('$pkg/pubspec.yaml'))) {
    problems.add('$pkg/pubspec.yaml version is not $v');
  }
  final constants = pkg == 'server'
      ? [('server/lib/src/version.dart', 'serverVersion')]
      : [
          ('client/lib/src/version.dart', 'clientVersion'),
          ('server/lib/src/version.dart', 'latestClientVersion'),
        ];
  for (final (file, name) in constants) {
    if (!read(file).contains("const $name = '$v';")) {
      problems.add('$file $name is not $v');
    }
  }
  if (pkg == 'client' &&
      read('client/lib/src/version.dart')
          .contains('firstPublicRelease = null')) {
    problems.add('client/lib/src/version.dart firstPublicRelease is not set');
  }
  if (!read('$pkg/CHANGELOG.md').contains('## [$v] - ')) {
    problems.add('$pkg/CHANGELOG.md has no [$v] section');
  }
  if (!Directory('${root.path}/shared/test/fixtures/v$v').existsSync()) {
    problems.add('no fixtures v$v');
  }
  return problems;
}

// The pubspec version without its `+build` part.
String _current(Directory root, String package) => _pubspecVersion
    .firstMatch(
      File('${root.path}/$package/pubspec.yaml').readAsStringSync(),
    )![1]!
    .split('+')
    .first;

String _resolve(String current, String level) {
  final [major, minor, patch] = current.split('.').map(int.parse).toList();
  return switch (level) {
    'patch' => '$major.$minor.${patch + 1}',
    'minor' => '$major.${minor + 1}.0',
    'major' => '${major + 1}.0.0',
    _ when _semver.hasMatch(level) => level,
    _ => throw ArgumentError.value(
      level,
      'level',
      'patch, minor, major or X.Y.Z',
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
    edit(
      'server/lib/src/version.dart',
      (t) => constant(t, 'serverVersion', version),
    );
  } else {
    edit(
      'client/lib/src/version.dart',
      (t) => constant(t, 'clientVersion', version).replaceFirst(
        'const String? firstPublicRelease = null;',
        "const String? firstPublicRelease = '$day';",
      ),
    );
    edit(
      'server/lib/src/version.dart',
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
