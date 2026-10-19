// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fake_mailer.dart';
import '../support/test_server.dart';

void main() {
  test('lockout mail: existing accounts only, at most one per hour', () async {
    final mailer = FakeMailer();
    final s = await TestServer.start(
      env: {
        'UNFEUDAL_SMTP_HOST': 'smtp.test',
        'UNFEUDAL_SMTP_FROM': 'vault@vault.test',
        'UNFEUDAL_LOGIN_MAX_ATTEMPTS': '3',
      },
      mailer: mailer,
    );
    addTearDown(s.close);
    final owner = await s.setupOwner();
    Future<int> fail(String email, String ip) async {
      final r = await s.post(
        '/api/v1/login',
        body: {
          'email': email,
          'authKey': b64(List.filled(32, 9)),
          'device': testDevice(),
        },
        ip: ip,
      );
      s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
      return r.status;
    }

    Future<List<MailKind>> kinds() async {
      await s.deps.notifier.drain(const Duration(seconds: 5));
      return [for (final m in mailer.sent) m.kind];
    }

    expect(
      [for (var i = 0; i < 4; i++) await fail(owner.email, '198.51.100.1')],
      [401, 401, 401, 429],
    );
    expect(await kinds(), [MailKind.lockout]);
    expect(mailer.sent.single.to, owner.email);
    s.clock.advance(const Duration(minutes: 16));
    for (var i = 0; i < 3; i++) {
      await fail(owner.email, '198.51.100.2');
    }
    expect(await kinds(), [
      MailKind.lockout,
    ], reason: 'mail:<userId> allows one per hour');
    s.clock.advance(const Duration(minutes: 45));
    for (var i = 0; i < 3; i++) {
      await fail(owner.email, '198.51.100.3');
    }
    expect(await kinds(), [MailKind.lockout, MailKind.lockout]);
    for (var i = 0; i < 3; i++) {
      await fail('ghost@example.org', '198.51.100.4');
    }
    expect(await kinds(), hasLength(2), reason: 'no mail for an unknown email');
  });
}
