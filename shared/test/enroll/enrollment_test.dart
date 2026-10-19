// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  const setupGrouped = 'abcd-efgh ijkl-mnop-qrst-uvwx-yz';
  const setup = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final invite = b64(List.filled(32, 7));
  final server = Uri.parse('https://vault.example.org');
  // That invite, sealed with 'file pass' under KdfParams.testing.
  final sealed = File('test/fixtures/v0/enrollment_encrypted.json')
      .readAsStringSync();

  test('normalizeSetupToken uppercases and drops spaces and dashes', () {
    expect(normalizeSetupToken(setupGrouped), setup);
  });

  test('link round-trips; missing kind means setup', () {
    final e = Enrollment(server, setupGrouped, EnrollKind.setup);
    expect(e.token, setup);
    final back = Enrollment.parseLink(e.toLink());
    expect(
      (back.server, back.token, back.kind),
      (server, setup, EnrollKind.setup),
    );
    final noKind = Enrollment.parseLink(
      'unfeudal://enroll?server=${Uri.encodeComponent('$server')}&token=$setup',
    );
    expect(noKind.kind, EnrollKind.setup);
    final inv = Enrollment.parseLink(
      Enrollment(server, invite, EnrollKind.invite).toLink(),
    );
    expect((inv.token, inv.kind), (invite, EnrollKind.invite));
  });

  test('http toward a public host is refused; LAN http is accepted', () {
    expect(
      () => Enrollment(
        Uri.parse('http://vault.example.org'),
        setup,
        EnrollKind.setup,
      ),
      throwsFormatException,
    );
    expect(
      () => Enrollment(Uri.parse('ftp://192.168.1.2'), setup, EnrollKind.setup),
      throwsFormatException,
    );
    expect(
      Enrollment(
        Uri.parse('http://192.168.1.2:8080'),
        setup,
        EnrollKind.setup,
      ).server.port,
      8080,
    );
  });

  test('bad links and tokens throw FormatException', () {
    final enc = Uri.encodeComponent('$server');
    for (final link in [
      'https://enroll?server=$enc&token=$setup',
      'unfeudal://other?server=$enc&token=$setup',
      'unfeudal://enroll?token=$setup',
      'unfeudal://enroll?server=$enc&token=ABC',
      'unfeudal://enroll?server=$enc&token=$setup&kind=invite',
      'unfeudal://enroll?server=$enc&token=$invite&kind=setup',
      'unfeudal://enroll?server=$enc&token=$setup&kind=admin',
    ]) {
      expect(
        () => Enrollment.parseLink(link),
        throwsFormatException,
        reason: link,
      );
    }
  });

  test('plain files round-trip; the encrypted fixture opens', () async {
    final plain = Enrollment(server, invite, EnrollKind.invite).toFile();
    expect(jsonDecode(plain), {
      'unfeudal-enroll': 1,
      'server': '$server',
      'token': invite,
      'kind': 'invite',
    });
    expect((await Enrollment.parseFile(plain)).token, invite);
    expect(sealed.contains(invite), isFalse);
    final back = await Enrollment.parseFile(
      sealed,
      passphrase: 'file pass',
      allowTestingKdf: true,
    );
    expect(
      (back.server, back.token, back.kind),
      (server, invite, EnrollKind.invite),
    );
  });

  test('wrong or missing passphrase throws WrongPassword', () async {
    await expectLater(
      Enrollment.parseFile(sealed, passphrase: 'nope', allowTestingKdf: true),
      throwsA(isA<WrongPassword>()),
    );
    await expectLater(
      Enrollment.parseFile(sealed, allowTestingKdf: true),
      throwsA(isA<WrongPassword>()),
    );
  });

  test('weak KDF in an encrypted file is refused before deriving', () async {
    await expectLater(
      Enrollment.parseFile(sealed, passphrase: 'file pass'),
      throwsA(isA<WeakKdf>()),
    );
  });

  test(
    'unknown file version is unsupported; garbage is a FormatException',
    () async {
      await expectLater(
        Enrollment.parseFile('{"unfeudal-enroll": 2}'),
        throwsA(isA<UnsupportedEnvelope>()),
      );
      for (final text in [
        'nope',
        '[]',
        '{"unfeudal-enroll": "1"}',
        '{"unfeudal-enroll": 1, "server": "https://x.org"}',
      ]) {
        await expectLater(
          Enrollment.parseFile(text),
          throwsFormatException,
          reason: text,
        );
      }
    },
  );
}
