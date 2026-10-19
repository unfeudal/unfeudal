// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/app.dart';
import '../auth/tokens.dart';
import '../config/features.dart';
import '../db/db.dart';
import '../mail/mailer.dart';
import '../util/random.dart';

typedef InviteRow = ({String id, String token, DateTime expiresAt});

/// One invite row, org or instance; only the token's hash is stored.
Future<InviteRow> createInviteRow(
  Tx tx,
  AppDeps deps, {
  required String email,
  String? orgId,
  String? role,
  required String createdBy,
}) async {
  final id = newId(), token = randomToken();
  final now = deps.clock.now();
  final expiresAt = now.add(deps.config.inviteTtl);
  await tx.execute(
    'INSERT INTO invites (id, token_hash, email, org_id, role, created_by, created_at, expires_at) '
    'VALUES (@id, @h, @e, @o, @r, @u, @t, @x)',
    {
      'id': id,
      'h': hashToken(token),
      'e': email,
      'o': orgId,
      'r': role,
      'u': createdBy,
      't': iso(now),
      'x': iso(expiresAt),
    },
  );
  return (id: id, token: token, expiresAt: expiresAt);
}

/// `{id, email, role, expiresAt, link, file}`: the link and the plain enrollment file carry the token.
Future<Map<String, Object?>> inviteBody(
  AppDeps deps,
  InviteRow row, {
  required String email,
  String? role,
}) async {
  final enrollment = Enrollment(
    deps.config.publicUrl,
    row.token,
    EnrollKind.invite,
  );
  return {
    'id': row.id,
    'email': email,
    'role': role,
    'expiresAt': iso(row.expiresAt),
    'link': enrollment.toLink(),
    'file': await enrollment.toFile(),
  };
}

/// Sent after commit; no SMTP or smtp_invites off: false, nothing logged. A failure is logged without
/// the body, the address or the link, and never undoes the invite.
Future<bool> inviteMailSent(
  AppDeps deps, {
  required String to,
  required String locale,
  required Map<String, String> vars,
}) async {
  if (deps.config.smtp == null || !deps.features.enabled(Flag.smtpInvites)) {
    return false;
  }
  try {
    return await deps.mailer.send(Mail(MailKind.invite, to, locale, vars));
  } catch (e) {
    deps.log.warn('invite mail failed', {'type': '${e.runtimeType}'});
    return false;
  }
}
