// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import '../config/config.dart';
import 'mailer.dart';
import 'templates.dart';

class SmtpMailer implements Mailer {
  SmtpMailer(this.config, {this.timezone = 'UTC'});

  static const _timeout = Duration(seconds: 20);

  final SmtpConfig config;
  final String timezone;

  /// `implicit`: TLS from the first byte. `starttls`: STARTTLS is required; a server that does not offer
  /// it, or refuses it, fails the send before any credential or address is sent. `none`: clear text.
  late final SmtpServer _server = SmtpServer(
    config.host,
    port: config.port,
    ssl: config.tls == SmtpTls.implicit,
    allowInsecure: config.tls == SmtpTls.none,
    username: config.user,
    password: config.password,
  );

  /// Throws on any failure: the caller logs it without the body (SecurityNotifier, inviteMailSent).
  @override
  Future<bool> send(Mail mail) async {
    final m = renderMail(mail, timezone);
    await mailer.send(
      mailer.Message()
        ..from = mailer.Address(config.from)
        ..recipients.add(mail.to)
        ..subject = m.subject
        ..text = m.text,
      _server,
      timeout: _timeout,
    );
    return true;
  }
}
