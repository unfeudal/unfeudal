// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_server/src/mail/templates.dart';

const t = '2026-10-13T12:00:00.000Z';
const security = [
  MailKind.newDevice,
  MailKind.passwordChanged,
  MailKind.recoveryUsed,
  MailKind.lockout,
];

Mail mail(MailKind kind, String locale, [Map<String, String>? vars]) => Mail(
  kind,
  'camille@example.org',
  locale,
  vars ??
      {
        'time': t,
        'device': 'Laptop',
        'platform': 'macos',
        'link': 'unfeudal://enroll?token=x',
        'orgName': 'Acme',
      },
);

void main() {
  test('every kind renders in en and fr with every placeholder filled', () {
    for (final kind in MailKind.values) {
      for (final locale in ['en', 'fr']) {
        final m = renderMail(mail(kind, locale), 'UTC');
        expect(m.subject, isNotEmpty);
        expect(
          '${m.subject}\n${m.text}',
          isNot(contains('{')),
          reason: '$kind $locale',
        );
      }
    }
  });

  test('times are shown in the instance timezone', () {
    expect(
      renderMail(mail(MailKind.passwordChanged, 'en'), 'Europe/Paris').text,
      contains('2026-10-13 14:00 (Europe/Paris)'),
    );
    expect(
      renderMail(mail(MailKind.passwordChanged, 'en'), 'UTC').text,
      contains('2026-10-13 12:00 (UTC)'),
    );
  });

  test('an unknown locale falls back to English', () {
    expect(
      renderMail(mail(MailKind.lockout, 'de'), 'UTC'),
      renderMail(mail(MailKind.lockout, 'en'), 'UTC'),
    );
  });

  test('security mails carry no link and no token', () {
    for (final kind in security) {
      for (final locale in ['en', 'fr']) {
        final m = renderMail(mail(kind, locale), 'UTC');
        expect(m.text, isNot(contains('://')), reason: '$kind $locale');
        expect(m.text, isNot(contains('token')), reason: '$kind $locale');
      }
    }
  });

  test('the invite carries its link, and the org name when there is one', () {
    final org = renderMail(mail(MailKind.invite, 'fr'), 'UTC').text;
    expect(org, allOf(contains('unfeudal://enroll?token=x'), contains('Acme')));
    final instance = renderMail(
      mail(MailKind.invite, 'en', {'link': 'unfeudal://enroll?token=y'}),
      'UTC',
    ).text;
    expect(instance, contains('unfeudal://enroll?token=y'));
  });

  test('French copy uses neutral forms', () {
    final personal = RegExp(
      r"(^|[\s'\u2019(])(tu|vous|votre|vos|ton|ta|tes|toi)(?=[\s.,;:!?)]|$)",
      caseSensitive: false,
    );
    for (final kind in MailKind.values) {
      final m = renderMail(mail(kind, 'fr'), 'UTC');
      expect(
        personal.hasMatch('${m.subject}\n${m.text}'),
        isFalse,
        reason: '$kind',
      );
    }
  });
}
