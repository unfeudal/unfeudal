// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/db/open_db.dart';
import 'package:unfeudal_server/src/log/logger.dart';
import 'package:unfeudal_server/src/run_server.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  late Directory dir;
  late Config config;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('unfeudal_run_');
    config = Config.load({
      'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
      'UNFEUDAL_DATABASE_URL':
          'sqlite:///${dir.path.replaceAll('\\', '/')}/u.db',
      'UNFEUDAL_SECRET_FILE': '${dir.path}/secret.key',
      'UNFEUDAL_LISTEN': '127.0.0.1:${await freePort()}',
    });
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('serves over HTTP; prints the setup token once and it works; healthcheck follows', () async {
    final lines = <String>[];
    final server = await runServer(
      config,
      log: Logger(LogLevel.info, lines.add),
    );
    final printed = lines.where((l) => l.startsWith('Setup token: ')).toList();
    expect(printed, hasLength(1));
    final token = printed.single.substring('Setup token: '.length);
    expect(token, matches(RegExp(r'^([A-Z2-7]{4}-){6}[A-Z2-7]{2}$')));
    expect(await healthcheck(config), 0);
    final acc = await AccountCrypto().create('correct horse battery');
    final client = HttpClient();
    final req = await client.post('127.0.0.1', server.port, '/api/v1/setup');
    req.headers
      ..contentType = ContentType.json
      ..set('x-unfeudal-client', '0.1.0');
    req.write(
      jsonEncode({
        'token': token,
        'email': 'o@vault.test',
        'bundle': acc.bundle.toJson(),
        'authKey': b64(acc.authKey),
        'recoveryAuthKey': b64(acc.recoveryAuthKey),
        'device': {'name': 'cli', 'platform': 'linux'},
      }),
    );
    final res = await req.close();
    expect(res.statusCode, 201);
    client.close();
    await server.close();
    expect(await healthcheck(config), 1);
    final again = <String>[];
    final second = await runServer(
      config,
      log: Logger(LogLevel.info, again.add),
    );
    expect(again.where((l) => l.startsWith('Setup token: ')), isEmpty);
    await second.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a newer database refuses to start', () async {
    final db = await openDb(config.databaseUrl);
    await migrate(db);
    await db.execute(
      "UPDATE meta SET value = '99' WHERE key = 'schema_version'",
    );
    await db.close();
    await expectLater(
      runServer(config, log: Logger(LogLevel.error, (_) {})),
      throwsA(isA<SchemaTooNew>()),
    );
  });

  test('the retention job runs at start', () async {
    final lines = <String>[];
    final server = await runServer(
      config,
      log: Logger(LogLevel.info, lines.add),
    );
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return !lines.any((l) => l.contains('retention done'));
    }).timeout(const Duration(seconds: 10));
    await server.close();
    expect(lines, contains(contains('retention done')));
  });
}
