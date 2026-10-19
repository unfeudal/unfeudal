// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

typedef SmtpMessage = ({String from, List<String> to, String data});

/// In-process SMTP server: records every command and message. With [advertiseStartTls] it offers
/// STARTTLS in EHLO but refuses it (454), which is enough to test that a client never falls back.
class FakeSmtpServer {
  FakeSmtpServer._(this._server, this.advertiseStartTls);
  final ServerSocket _server;
  final bool advertiseStartTls;
  final commands = <String>[];
  final messages = <SmtpMessage>[];
  int get port => _server.port;

  static Future<FakeSmtpServer> start({bool advertiseStartTls = false}) async {
    final s = FakeSmtpServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      advertiseStartTls,
    );
    s._server.listen(s._serve);
    return s;
  }

  Future<void> _serve(Socket socket) async {
    void say(String line) => socket.write('$line\r\n');
    say('220 fake ESMTP');
    String? from;
    final to = <String>[];
    StringBuffer? data;
    var authContinues = false;
    try {
      await for (final line
          in socket
              .cast<List<int>>()
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())) {
        if (data != null) {
          if (line == '.') {
            messages.add((from: from!, to: List.of(to), data: data.toString()));
            data = null;
            say('250 queued');
          } else {
            data.writeln(line.startsWith('..') ? line.substring(1) : line);
          }
          continue;
        }
        commands.add(line);
        if (authContinues) {
          authContinues = false;
          say('235 ok');
          continue;
        }
        final verb = line.split(' ').first.toUpperCase();
        switch (verb) {
          case 'EHLO':
            socket.write(
              '250-fake\r\n${advertiseStartTls ? '250-STARTTLS\r\n' : ''}250 AUTH PLAIN\r\n',
            );
          case 'HELO':
            say('250 fake');
          case 'STARTTLS':
            say('454 TLS not available');
          case 'AUTH':
            if (line.trim().split(' ').length == 2) {
              authContinues = true;
              say('334 ');
            } else {
              say('235 ok');
            }
          case 'MAIL':
            from = RegExp('<([^>]*)>').firstMatch(line)?[1];
            say('250 ok');
          case 'RCPT':
            to.add(RegExp('<([^>]*)>').firstMatch(line)![1]!);
            say('250 ok');
          case 'DATA':
            data = StringBuffer();
            say('354 go');
          case 'QUIT':
            say('221 bye');
            await socket.close();
            return;
          default:
            say('502 unsupported');
        }
      }
    } on SocketException {
      // the client hung up
    }
  }

  Future<void> close() => _server.close();
}
