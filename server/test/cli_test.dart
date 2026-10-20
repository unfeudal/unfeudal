// SPDX-License-Identifier: AGPL-3.0-or-later
// Windows: the child `dart run` rebuilds sqlite3.dll, which this test runner already holds open.
@OnPlatform({
  'windows': Skip(
    'dart run cannot replace a loaded sqlite3.dll; runs in Linux CI',
  ),
})
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';

/// The parent environment without any UNFEUDAL_* variable, plus [env].
Future<ProcessResult> cli(List<String> args, Map<String, String> env) =>
    Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/server.dart', ...args],
      environment: {
        for (final e in Platform.environment.entries)
          if (!e.key.toUpperCase().startsWith('UNFEUDAL_')) e.key: e.value,
        ...env,
      },
      includeParentEnvironment: false,
    );

void main() {
  late Directory dir;
  late Map<String, String> env;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('unfeudal_cli_');
    env = {
      'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
      'UNFEUDAL_DATABASE_URL':
          'sqlite:///${dir.path.replaceAll('\\', '/')}/u.db',
      'UNFEUDAL_SECRET_FILE': '${dir.path}/secret.key',
    };
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'config errors exit 2 naming the key; unknown commands exit 64',
    () async {
      final missing = await cli([
        'new-epoch',
      ], {...env}..remove('UNFEUDAL_PUBLIC_URL'));
      expect(missing.exitCode, 2);
      expect('${missing.stderr}', contains('public_url'));
      final unknown = await cli(
        ['new-epoch'],
        {...env, 'UNFEUDAL_COLOUR': 'blue'},
      );
      expect(unknown.exitCode, 2);
      expect('${unknown.stderr}', contains('UNFEUDAL_COLOUR'));
      final file = File('${dir.path}/c.yaml')
        ..writeAsStringSync('log_level: loud\n');
      final yaml = await cli(
        ['new-epoch'],
        {...env, 'UNFEUDAL_CONFIG_FILE': file.path},
      );
      expect(yaml.exitCode, 2);
      expect('${yaml.stderr}', contains('log_level'));
      expect((await cli(['frobnicate'], env)).exitCode, 64);
    },
  );

  test('new-epoch prints a new epoch; backup writes once', () async {
    final a = await cli(['new-epoch'], env);
    final b = await cli(['new-epoch'], env);
    expect((a.exitCode, b.exitCode), (0, 0));
    expect('${a.stdout}'.trim(), matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    expect('${a.stdout}', isNot('${b.stdout}'));
    final target = '${dir.path}/backup.db';
    expect((await cli(['backup', target], env)).exitCode, 0);
    expect(File(target).existsSync(), isTrue);
    expect((await cli(['backup', target], env)).exitCode, 1);
  });

  test('transfer-owner: usage 64, unknown email 1, success 0', () async {
    expect((await cli(['transfer-owner'], env)).exitCode, 64);
    expect(
      (await cli(['transfer-owner', 'ghost@vault.test'], env)).exitCode,
      1,
    );
    final db = await openDb(env['UNFEUDAL_DATABASE_URL']!);
    await migrate(db);
    for (final (id, email, io) in [
      ('a', 'a@vault.test', 1),
      ('b', 'b@vault.test', 0),
    ]) {
      await db.execute(
        'INSERT INTO users (id, email, is_instance_owner, bundle, auth_hash, created_at) '
        "VALUES (@i, @e, @o, '{}', 'h', '2026-10-13T12:00:00.000Z')",
        {'i': id, 'e': email, 'o': io},
      );
    }
    await db.close();
    final ok = await cli(['transfer-owner', ' B@Vault.test '], env);
    expect(ok.exitCode, 0);
    expect('${ok.stdout}', contains('b@vault.test'));
  });
}
