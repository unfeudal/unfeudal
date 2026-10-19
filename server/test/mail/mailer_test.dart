// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';

import '../support/fake_mailer.dart';
import '../support/test_server.dart';

void main() {
  test('NoMailer sends nothing and answers false', () async {
    expect(
      await const NoMailer().send(
        const Mail(MailKind.invite, 'a@b.c', 'en', {'link': 'x'}),
      ),
      isFalse,
    );
  });

  test(
    'AppDeps carries the mailer; runServer and AppDeps default to NoMailer',
    () async {
      final fake = FakeMailer();
      final s = await TestServer.start(mailer: fake);
      addTearDown(s.close);
      expect(s.deps.mailer, same(fake));
    },
  );

  test('Mail keeps kind, recipient, locale and vars', () {
    const m = Mail(MailKind.invite, 'a@b.c', 'fr', {
      'link': 'unfeudal://enroll',
    });
    expect(
      (m.kind, m.to, m.locale, m.vars['link']),
      (MailKind.invite, 'a@b.c', 'fr', 'unfeudal://enroll'),
    );
    expect(MailKind.values.map((k) => k.name), [
      'invite',
      'newDevice',
      'passwordChanged',
      'recoveryUsed',
      'lockout',
    ]);
  });
}
