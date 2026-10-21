// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_tool/release.dart';

Directory createRepo() {
  final root = Directory.systemTemp.createTempSync('uf_tool_');
  addTearDown(() => root.deleteSync(recursive: true));
  void write(String path, String text) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  write('server/pubspec.yaml', 'name: unfeudal_server\nversion: 0.1.0\n');
  write(
    'server/lib/src/version.dart',
    "const serverVersion = '0.1.0';\nconst latestClientVersion = '0.1.0';\n",
  );
  write('client/pubspec.yaml', 'name: unfeudal_client\nversion: 1.0.0+1\n');
  write(
    'client/lib/src/version.dart',
    "const clientVersion = '0.1.0';\nconst clientApis = [1];\nconst String? firstPublicRelease = null;\n",
  );
  write(
    'server/CHANGELOG.md',
    '# Changelog\n\n## [Unreleased]\n### Added\n- Mail.\n',
  );
  write('client/CHANGELOG.md', '# Changelog\n\n## [Unreleased]\n');
  write('shared/test/fixtures/v0/api_info.json', '{}\n');
  return root;
}

String read(Directory root, String path) =>
    File('${root.path}/$path').readAsStringSync();
final day = DateTime.utc(2026, 11, 2);

void main() {
  group('bump client', () {
    late Directory root;
    late String bumped;
    setUp(() {
      root = createRepo();
      bumped = bump(root, 'client', '0.2.0', date: day);
    });

    test('writes pubspec, clientVersion, changelog and fixtures', () {
      expect(bumped, '0.2.0');
      expect(
        read(root, 'client/pubspec.yaml'),
        'name: unfeudal_client\nversion: 0.2.0\n',
      );
      expect(
        read(root, 'client/lib/src/version.dart'),
        contains("const clientVersion = '0.2.0';"),
      );
      expect(
        read(root, 'client/CHANGELOG.md'),
        '# Changelog\n\n## [Unreleased]\n\n## [0.2.0] - 2026-11-02\n',
      );
      expect(read(root, 'shared/test/fixtures/v0.2.0/api_info.json'), '{}\n');
    });

    test('releases a server patch announcing the client', () {
      expect(
        read(root, 'server/lib/src/version.dart'),
        "const serverVersion = '0.1.1';\nconst latestClientVersion = '0.2.0';\n",
      );
      expect(
        read(root, 'server/CHANGELOG.md'),
        contains(
          '## [0.1.1] - 2026-11-02\n### Added\n- Mail.\n### Changed\n- Announces client 0.2.0.\n',
        ),
      );
    });

    test('sets firstPublicRelease once', () {
      expect(
        read(root, 'client/lib/src/version.dart'),
        contains("const String? firstPublicRelease = '2026-11-02';"),
      );
      bump(root, 'client', '0.3.0', date: DateTime.utc(2027, 1, 5));
      expect(
        read(root, 'client/lib/src/version.dart'),
        contains("const String? firstPublicRelease = '2026-11-02';"),
      );
    });
  });

  test('bump server: pubspec and serverVersion only; the notes move under the version', () {
    final root = createRepo();
    expect(bump(root, 'server', '0.1.1', date: day), '0.1.1');
    expect(
      read(root, 'server/lib/src/version.dart'),
      "const serverVersion = '0.1.1';\nconst latestClientVersion = '0.1.0';\n",
    );
    expect(
      read(root, 'server/CHANGELOG.md'),
      '# Changelog\n\n## [Unreleased]\n\n## [0.1.1] - 2026-11-02\n### Added\n- Mail.\n',
    );
  });

  test('patch, minor and major resolve from the current version', () {
    // createRepo starts the server at 0.1.0.
    final root = createRepo();
    expect(bump(root, 'server', 'patch', date: day), '0.1.1');
    expect(bump(root, 'server', 'minor', date: day), '0.2.0');
    expect(bump(root, 'server', 'major', date: day), '1.0.0');
  });

  test('a bad package is refused', () {
    expect(
      () => bump(createRepo(), 'tool', '1.0.0', date: day),
      throwsArgumentError,
    );
  });

  test('a bad version is refused', () {
    final root = createRepo();
    for (final level in ['1.0', '1.0.0+1', '1.0.0-beta', 'huge']) {
      expect(
        () => bump(root, 'client', level, date: day),
        throwsFormatException,
        reason: level,
      );
    }
  });

  group('checkTag', () {
    test('rejects a tag that is not server-vX.Y.Z or client-vX.Y.Z', () {
      expect(checkTag(createRepo(), 'v0.2.0'), [contains('tag')]);
    });

    test('passes for both tags after a client bump', () {
      final root = createRepo();
      bump(root, 'client', '0.2.0', date: day);
      expect(checkTag(root, 'client-v0.2.0'), isEmpty);
      expect(checkTag(root, 'server-v0.1.1'), isEmpty);
    });

    test('reports the missing CHANGELOG section and fixtures for an unreleased version', () {
      expect(checkTag(createRepo(), 'server-v0.1.0'), [
        contains('CHANGELOG'),
        contains('fixtures'),
      ]);
    });

    test('reports an unset firstPublicRelease', () {
      final root = createRepo();
      bump(root, 'client', '0.2.0', date: day);
      File('${root.path}/client/lib/src/version.dart').writeAsStringSync(
        read(
          root,
          'client/lib/src/version.dart',
        ).replaceFirst("'2026-11-02'", 'null'),
      );
      expect(checkTag(root, 'client-v0.2.0'), [contains('firstPublicRelease')]);
    });
  });
}
