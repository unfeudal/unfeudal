// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';
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
  test(
    'close lets an in-flight request finish, then refuses new connections',
    () async {
      final dir = Directory.systemTemp.createTempSync('unfeudal_stop_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = Config.load({
        'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
        'UNFEUDAL_DATABASE_URL':
            'sqlite:///${dir.path.replaceAll('\\', '/')}/u.db',
        'UNFEUDAL_SECRET_FILE': '${dir.path}/secret.key',
        'UNFEUDAL_LISTEN': '127.0.0.1:${await freePort()}',
      });
      final server = await runServer(
        config,
        log: Logger(LogLevel.error, (_) {}),
      );
      final client = HttpClient();
      addTearDown(client.close);

      /// Sends half of the body, waits for [between], then the rest.
      Future<int> login(
        String email, [
        Future<void> Function()? between,
      ]) async {
        final req = await client.post(
          '127.0.0.1',
          server.port,
          '/api/v1/login',
        );
        req.headers
          ..contentType = ContentType.json
          ..set('x-unfeudal-client', '0.1.0');
        final body = jsonEncode({
          'email': email,
          'authKey': b64(List.filled(32, 1)),
          'device': {'name': 'n', 'platform': 'linux'},
        });
        req.write(body.substring(0, 20));
        await req.flush();
        await between?.call();
        req.write(body.substring(20));
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      }

      expect(await login('ghost@vault.test'), 401);
      final sw = Stopwatch()..start();
      late Future<void> closing;
      // the request is still reading its body when close starts
      final inFlight = login('late@vault.test', () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        closing = server.close();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      expect(await inFlight, 401);
      await closing;
      expect(sw.elapsed, lessThan(const Duration(seconds: 8)));
      await expectLater(
        Socket.connect('127.0.0.1', server.port),
        throwsA(isA<SocketException>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
