// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One app per user account: two instances would share one device session and the second refresh would
/// replay a rotated token, which revokes the device. The first instance listens on a loopback port written
/// in [portFile]; a later launch knocks there, the first one comes forward, the later one exits.
class SingleInstance {
  SingleInstance._(this._server);

  final ServerSocket _server;

  static const _knock = 'unfeudal-show';
  static const _answer = 'unfeudal-here';

  /// The running instance, or null when another one answered the knock.
  static Future<SingleInstance?> claim(
    String dir, {
    required void Function() onKnock,
  }) async {
    final portFile = File(p.join(dir, 'instance.port'));
    if (await _knockAt(portFile)) return null;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await portFile.writeAsString('${server.port}', flush: true);
    server.listen((client) async {
      try {
        final line = await utf8.decoder
            .bind(client)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 2));
        if (line == _knock) {
          client.writeln(_answer);
          await client.flush();
          onKnock();
        }
      } on Object {
        // a stranger on the port, or a knock cut short: nothing to show
      } finally {
        client.destroy();
      }
    });
    return SingleInstance._(server);
  }

  // True when a live instance answered; a stale port file or another program on that port is not one.
  static Future<bool> _knockAt(File portFile) async {
    final port = int.tryParse(
      await portFile.exists() ? (await portFile.readAsString()).trim() : '',
    );
    if (port == null) return false;
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.writeln(_knock);
      await socket.flush();
      final reply = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => '');
      socket.destroy();
      return reply == _answer;
    } on Object {
      return false;
    }
  }

  Future<void> close() => _server.close();
}
