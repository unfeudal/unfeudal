// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/app.dart';
import '../api/errors.dart';
import '../auth/rate_limit.dart';
import 'mailer.dart';

class SecurityNotifier {
  SecurityNotifier(this.deps);
  final AppDeps deps;
  final _pending = <Future<void>>{};

  bool get _on =>
      deps.config.smtp != null && deps.features.enabled(Flag.securityEmails);

  /// Call after the commit. Returns at once; reads the address and locale when the job runs.
  void notify(
    String userId,
    MailKind kind, [
    Map<String, String> vars = const {},
  ]) {
    if (!_on) return;
    final time = iso(deps.clock.now());
    _queue(kind, () async {
      final row = (await deps.db.query(
        'SELECT email, locale FROM users WHERE id = @u',
        {'u': userId},
      )).firstOrNull;
      if (row == null) return;
      await deps.mailer.send(
        Mail(kind, row['email']! as String, row['locale']! as String, {
          ...vars,
          'time': time,
        }),
      );
    });
  }

  /// RateLimiter.onLockout: existing accounts only; `mail:<userId>` allows one per hour, a refused hit skips the mail.
  void lockout(String email) {
    if (!_on) return;
    final time = iso(deps.clock.now());
    _queue(MailKind.lockout, () async {
      final row = (await deps.db.query(
        'SELECT id, locale FROM users WHERE email = @e',
        {'e': email},
      )).firstOrNull;
      if (row == null) return;
      try {
        await deps.limiter.hit([mailKey(row['id']! as String)]);
      } on ApiError {
        return;
      }
      await deps.mailer.send(
        Mail(MailKind.lockout, email, row['locale']! as String, {'time': time}),
      );
    });
  }

  void _queue(MailKind kind, Future<void> Function() job) {
    late final Future<void> f;
    f = Future(job)
        .catchError((Object e) {
          // The log never carries the address or the body.
          deps.log.warn('mail failed', {
            'kind': kind.name,
            'type': '${e.runtimeType}',
          });
        })
        .whenComplete(() => _pending.remove(f));
    _pending.add(f);
  }

  /// Waits for the queued mails, at most [budget].
  Future<void> drain(Duration budget) =>
      Future.wait(_pending.toList())
          .timeout(budget, onTimeout: () => const <void>[]);
}
