// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_server/src/mail/smtp_mailer.dart';

import '../support/fake_smtp.dart';

const mail = Mail(MailKind.passwordChanged, 'camille@example.org', 'fr', {
  'time': '2026-10-13T12:00:00.000Z',
});

SmtpConfig config(FakeSmtpServer f, SmtpTls tls) => (
  host: '127.0.0.1',
  port: f.port,
  tls: tls,
  user: 'mailer',
  password: 'p4ss-word',
  from: 'vault@vault.test',
);

bool sensitive(String command) {
  final c = command.toUpperCase();
  return c.startsWith('AUTH') ||
      c.startsWith('MAIL') ||
      c.startsWith('RCPT') ||
      c.startsWith('DATA');
}

void main() {
  late FakeSmtpServer smtp;
  tearDown(() => smtp.close());

  test('none: one message from smtp_from to the recipient, authenticated, UTF-8 subject encoded', () async {
    smtp = await FakeSmtpServer.start();
    expect(
      await SmtpMailer(
        config(smtp, SmtpTls.none),
        timezone: 'Europe/Paris',
      ).send(mail),
      isTrue,
    );
    final m = smtp.messages.single;
    expect(m.from, 'vault@vault.test');
    expect(m.to, ['camille@example.org']);
    expect(
      smtp.commands.where((c) => c.toUpperCase().startsWith('AUTH')),
      hasLength(1),
    );
    expect(
      m.data,
      matches(
        RegExp(
          r'^Subject: =\?utf-8\?[BQ]\?',
          caseSensitive: false,
          multiLine: true,
        ),
      ),
    );
    final body = m.data
        .substring(m.data.indexOf('\n\n'))
        .replaceAll('\n', ''); // base64 transfer encoding
    expect(utf8.decode(base64.decode(body)), contains('14:00'));
  });

  test(
    'starttls: a server without STARTTLS is refused before AUTH or MAIL',
    () async {
      smtp = await FakeSmtpServer.start();
      await expectLater(
        SmtpMailer(config(smtp, SmtpTls.starttls), timezone: 'UTC').send(mail),
        throwsA(anything),
      );
      expect(smtp.commands.where(sensitive), isEmpty);
      expect(smtp.messages, isEmpty);
    },
  );

  test('starttls: a refused STARTTLS is never followed by AUTH', () async {
    smtp = await FakeSmtpServer.start(advertiseStartTls: true);
    await expectLater(
      SmtpMailer(config(smtp, SmtpTls.starttls), timezone: 'UTC').send(mail),
      throwsA(anything),
    );
    expect(smtp.commands.map((c) => c.toUpperCase()), contains('STARTTLS'));
    expect(smtp.commands.where(sensitive), isEmpty);
  });

  test(
    'implicit: a plain-text server fails the TLS handshake; nothing is sent',
    () async {
      smtp = await FakeSmtpServer.start();
      await expectLater(
        SmtpMailer(config(smtp, SmtpTls.implicit), timezone: 'UTC').send(mail),
        throwsA(anything),
      );
      expect(smtp.messages, isEmpty);
    },
  );
}
