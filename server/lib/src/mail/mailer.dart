// SPDX-License-Identifier: AGPL-3.0-or-later

enum MailKind { invite, newDevice, passwordChanged, recoveryUsed, lockout }

class Mail {
  const Mail(this.kind, this.to, this.locale, this.vars);

  final MailKind kind;
  final String to;
  final String locale;

  /// Template values; never logged (an invite link is a credential).
  final Map<String, String> vars;
}

abstract class Mailer {
  /// True once the mail is handed to the server; a failure throws or answers false, never rolls back.
  Future<bool> send(Mail mail);
}

/// No `smtp_host`: nothing is sent and nothing is logged.
class NoMailer implements Mailer {
  const NoMailer();

  @override
  Future<bool> send(Mail mail) async => false;
}
