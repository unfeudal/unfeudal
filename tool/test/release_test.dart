// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_tool/release.dart';

Directory repo() {
  final d = Directory.systemTemp.createTempSync('uf_tool_');
  void w(String path, String text) => File('${d.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  w('server/pubspec.yaml', 'name: unfeudal_server\nversion: 0.1.0\n');
  w(
    'server/lib/src/version.dart',
    "const serverVersion = '0.1.0';\nconst latestClientVersion = '0.1.0';\n",
  );
  w('client/pubspec.yaml', 'name: unfeudal_client\nversion: 1.0.0+1\n');
  w(
    'client/lib/src/version.dart',
    "const clientVersion = '0.1.0';\nconst clientApis = [1];\nconst String? firstPublicRelease = null;\n",
  );
  w(
    'server/CHANGELOG.md',
    '# Changelog\n\n## [Unreleased]\n### Added\n- Mail.\n',
  );
  w('client/CHANGELOG.md', '# Changelog\n\n## [Unreleased]\n');
  w('shared/test/fixtures/v0/api_info.json', '{}\n');
  return d;
}

String read(Directory d, String path) =>
    File('${d.path}/$path').readAsStringSync();
final day = DateTime.utc(2026, 11, 2);

void main() {
  test('bump client: pubspec, clientVersion, changelog, fixtures, firstPublicRelease once, and the server patch announcing it', () {
    final d = repo();
    expect(bump(d, 'client', '0.2.0', date: day), [
      ('client', '0.2.0'),
      ('server', '0.1.1'),
    ]);
    expect(
      read(d, 'client/pubspec.yaml'),
      'name: unfeudal_client\nversion: 0.2.0\n',
    );
    expect(
      read(d, 'client/lib/src/version.dart'),
      contains("const clientVersion = '0.2.0';"),
    );
    expect(
      read(d, 'server/lib/src/version.dart'),
      "const serverVersion = '0.1.1';\nconst latestClientVersion = '0.2.0';\n",
    );
    expect(
      read(d, 'server/CHANGELOG.md'),
      contains(
        '## [0.1.1] - 2026-11-02\n### Added\n- Mail.\n### Changed\n- Announces client 0.2.0.\n',
      ),
    );
    expect(
      read(d, 'client/CHANGELOG.md'),
      '# Changelog\n\n## [Unreleased]\n\n## [0.2.0] - 2026-11-02\n',
    );
    expect(read(d, 'shared/test/fixtures/v0.2.0/api_info.json'), '{}\n');
    expect(
      read(d, 'client/lib/src/version.dart'),
      contains("const String? firstPublicRelease = '2026-11-02';"),
    );
    bump(d, 'client', '0.3.0', date: DateTime.utc(2027, 1, 5));
    expect(
      read(d, 'client/lib/src/version.dart'),
      contains("const String? firstPublicRelease = '2026-11-02';"),
    );
  });

  test('bump server: pubspec and serverVersion only; the notes move under the version', () {
    final d = repo();
    expect(bump(d, 'server', '0.1.1', date: day), [('server', '0.1.1')]);
    expect(
      read(d, 'server/lib/src/version.dart'),
      "const serverVersion = '0.1.1';\nconst latestClientVersion = '0.1.0';\n",
    );
    expect(
      read(d, 'server/CHANGELOG.md'),
      '# Changelog\n\n## [Unreleased]\n\n## [0.1.1] - 2026-11-02\n### Added\n- Mail.\n',
    );
  });

  test('patch, minor and major resolve from the current version', () {
    final d = repo(); // server 0.1.0
    expect(bump(d, 'server', 'patch', date: day), [('server', '0.1.1')]);
    expect(bump(d, 'server', 'minor', date: day), [('server', '0.2.0')]);
    expect(bump(d, 'server', 'major', date: day), [('server', '1.0.0')]);
  });

  test('a bad package or version is refused', () {
    final d = repo();
    for (final (pkg, v) in [
      ('tool', '1.0.0'),
      ('client', '1.0'),
      ('client', '1.0.0+1'),
      ('client', '1.0.0-beta'),
      ('client', 'huge'),
    ]) {
      expect(
        () => bump(d, pkg, v, date: day),
        throwsArgumentError,
        reason: '$pkg $v',
      );
    }
  });

  test('checkTag: versions, constant, changelog section and fixtures must all match the tag', () {
    final d = repo();
    expect(checkTag(d, 'client-v0.2.0'), isNotEmpty);
    bump(d, 'client', '0.2.0', date: day);
    expect(checkTag(d, 'client-v0.2.0'), isEmpty);
    expect(checkTag(d, 'server-v0.1.1'), isEmpty);
    expect(checkTag(repo(), 'server-v0.1.0'), [
      contains('CHANGELOG'),
      contains('fixtures'),
    ]);
    expect(checkTag(d, 'v0.2.0'), [contains('tag')]);
    final unset = repo();
    bump(unset, 'client', '0.2.0', date: day);
    File('${unset.path}/client/lib/src/version.dart').writeAsStringSync(
      read(
        unset,
        'client/lib/src/version.dart',
      ).replaceFirst("'2026-11-02'", 'null'),
    );
    expect(checkTag(unset, 'client-v0.2.0'), [contains('firstPublicRelease')]);
  });
}
