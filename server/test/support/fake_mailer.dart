// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_server/src/mail/mailer.dart';

class FakeMailer implements Mailer {
  final sent = <Mail>[];
  bool fail = false; // true: send throws, as a dead SMTP server would
  @override
  Future<bool> send(Mail mail) async {
    if (fail) throw StateError('smtp down');
    sent.add(mail);
    return true;
  }
}
