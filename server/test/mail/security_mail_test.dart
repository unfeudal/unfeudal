// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fake_mailer.dart';
import '../support/test_server.dart';

const smtpEnv = {
  'UNFEUDAL_SMTP_HOST': 'smtp.test',
  'UNFEUDAL_SMTP_FROM': 'vault@vault.test',
};

class GatedMailer implements Mailer {
  final gate = Completer<void>();
  final sent = <Mail>[];
  @override
  Future<bool> send(Mail mail) async {
    await gate.future;
    sent.add(mail);
    return true;
  }
}

void main() {
  late TestServer s;
  late TestSession owner;
  late FakeMailer mailer;
  Future<void> start([Map<String, String> env = smtpEnv]) async {
    mailer = FakeMailer();
    s = await TestServer.start(env: env, mailer: mailer);
    owner = await s.setupOwner();
  }

  Future<List<Mail>> sent() async {
    await s.deps.notifier.drain(const Duration(seconds: 5));
    return mailer.sent;
  }

  tearDown(() => s.close());

  test(
    'login sends newDevice in the account locale; setup sends none',
    () async {
      await start();
      expect(await sent(), isEmpty);
      await s.db.execute("UPDATE users SET locale = 'fr'");
      await s.login(owner.email, testPassword, deviceName: 'Laptop');
      final m = (await sent()).single;
      expect(
        (
          m.kind,
          m.to,
          m.locale,
          m.vars['device'],
          m.vars['platform'],
          m.vars['time'],
        ),
        (
          MailKind.newDevice,
          owner.email,
          'fr',
          'Laptop',
          'linux',
          iso(s.clock.now()),
        ),
      );
    },
  );

  test(
    'password change and recovery send their mail; a refused change sends none',
    () async {
      await start();
      final changed = await testCrypto.changePassword(
        owner.account,
        owner.bundle,
        'new password!',
      );
      final current = (await deriveMasterKeys(
        testPassword,
        owner.bundle.salt,
        owner.bundle.kdf,
      )).authKey;
      Map<String, Object?> body(List<int> key) => {
        'currentAuthKey': b64(key),
        'bundle': changed.bundle.toJson(),
        'bundleVersion': 0,
        'authKey': b64(changed.authKey),
      };
      expect(
        (await s.post(
          '/api/v1/account/password',
          token: owner.accessToken,
          body: body(List.filled(32, 3)),
        )).status,
        403,
      );
      expect(await sent(), isEmpty);
      s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
      expect(
        (await s.post(
          '/api/v1/account/password',
          token: owner.accessToken,
          body: body(current),
        )).status,
        204,
      );
      final unlocked = await testCrypto.unlockWithRecovery(
        changed.bundle,
        owner.recoveryKey!,
      );
      final reset = await testCrypto.changePassword(
        unlocked,
        changed.bundle,
        'fresh password',
      );
      final rotated = await testCrypto.rotateRecoveryKey(
        unlocked,
        reset.bundle,
      );
      final recovered = await s.post(
        '/api/v1/account/recover',
        body: {
          'email': owner.email,
          'recoveryAuthKey': b64(
            await recoveryAuthKey(RecoveryKey.decode(owner.recoveryKey!)),
          ),
          'bundle': rotated.bundle.toJson(),
          'bundleVersion': 1,
          'authKey': b64(reset.authKey),
          'newRecoveryAuthKey': b64(rotated.recoveryAuthKey),
        },
      );
      expect(recovered.status, 204);
      expect((await sent()).map((m) => m.kind), [
        MailKind.passwordChanged,
        MailKind.recoveryUsed,
      ]);
    },
  );

  test('no smtp_host: nothing sent, nothing logged', () async {
    await start(const {});
    await s.login(owner.email, testPassword);
    expect(await sent(), isEmpty);
    expect(s.logLines.where((l) => l.contains('mail')), isEmpty);
  });

  test('security_emails off: nothing sent', () async {
    await start({...smtpEnv, 'UNFEUDAL_FEATURE_SECURITY_EMAILS': 'false'});
    await s.login(owner.email, testPassword);
    expect(await sent(), isEmpty);
  });

  test('a failing mailer never changes the answer; the log has no address and no body', () async {
    await start();
    mailer.fail = true;
    final session = await s.login(
      owner.email,
      testPassword,
      deviceName: 'Laptop',
    );
    expect(session.deviceId, isNotEmpty);
    await sent();
    final line = s.logLines.singleWhere((l) => l.contains('mail failed'));
    expect(jsonDecode(line), {
      'level': 'warn',
      'msg': 'mail failed',
      'kind': 'newDevice',
      'type': 'StateError',
    });
  });

  test('drain waits for queued mails up to the budget', () async {
    final gated = GatedMailer();
    s = await TestServer.start(env: smtpEnv, mailer: gated);
    owner = await s.setupOwner();
    await s.login(owner.email, testPassword);
    final sw = Stopwatch()..start();
    await s.deps.notifier.drain(const Duration(milliseconds: 300));
    expect(sw.elapsed < const Duration(seconds: 2), true);
    expect(gated.sent, isEmpty);
    gated.gate.complete();
    await s.deps.notifier.drain(const Duration(seconds: 5));
    expect(gated.sent, hasLength(1));
  });
}
