// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../describe_error.dart';
import '../fields.dart';
import '../lock/lock_frame.dart';
import 'recovery_kit_view.dart';
import 'setup_screen.dart';

/// A new master password from the recovery key; every device is signed out and a new key is shown.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  late final TextEditingController _server;
  late final TextEditingController _email;
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _problem;
  ({String key, Uri server, String email})? _done;

  /// 1: server, e-mail and key; 2: the new password.
  int _step = 1;

  @override
  void initState() {
    super.initState();
    final stored = AppScope.read(context).stored;
    _server = TextEditingController(text: stored?.serverUrl.toString());
    _email = TextEditingController(text: stored?.email);
  }

  @override
  void dispose() {
    for (final c in [_server, _email, _key, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A mistyped key is refused here, before any request.
  void _next() {
    final l = AppLocalizations.of(context);
    try {
      RecoveryKey.decode(_key.text);
    } on InvalidRecoveryKey catch (e) {
      return setState(() => _problem = describeError(l, e));
    }
    setState(() {
      _problem = null;
      _step = 2;
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final local = checkNewPassword(l, _password.text, _confirm.text);
    if (local != null) return setState(() => _problem = local);
    setState(() {
      _busy = true;
      _problem = null;
    });
    final server = Uri.parse(_server.text.trim());
    final email = _email.text.trim();
    try {
      final key = await AppScope.read(context).recover(
        server: server,
        email: email,
        recoveryKey: _key.text,
        newPassword: _password.text,
      );
      if (mounted) {
        setState(() => _done = (key: key, server: server, email: email));
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    final messenger = ScaffoldMessenger.of(context);
    final done = AppLocalizations.of(context).recoverDone;
    Navigator.of(context).maybePop();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_done case final done?) {
      return RecoveryKitView(
        recoveryKey: done.key,
        server: done.server,
        email: done.email,
        onDone: _finish,
      );
    }
    final first = _step == 1;
    return Scaffold(
      body: LockFrame(
        step: l.stepOf(_step, 2),
        title: first ? l.recoverTitle : l.recoverPasswordTitle,
        subtitle: first ? l.recoverSubtitle : l.recoverPasswordSubtitle,
        children: [
          if (first) ...[
            keyedField(
              'recover-server',
              _server,
              l.loginServer,
              keyboard: TextInputType.url,
            ),
            keyedField(
              'recover-email',
              _email,
              l.loginEmail,
              keyboard: TextInputType.emailAddress,
            ),
            keyedField(
              'recover-key',
              _key,
              l.recoverKey,
              mono: true,
              hint: 'XXXX-XXXX-XXXX-XXXX-…',
              onSubmitted: (_) => _next(),
            ),
          ] else ...[
            keyedField(
              'recover-password',
              _password,
              l.recoverNewPassword,
              secret: true,
            ),
            keyedField(
              'recover-confirm',
              _confirm,
              l.setupConfirm,
              secret: true,
            ),
            LockNotice(l.setupWarning),
          ],
          if (_problem case final problem?) LockError(problem),
          if (first)
            LockActions(
              primary: FilledButton(
                key: const Key('recover-next'),
                onPressed: _next,
                child: Text(l.stepNext),
              ),
              links: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(l.cancel),
                ),
              ],
            )
          else
            LockActions(
              primary: FilledButton(
                key: const Key('recover-submit'),
                onPressed: _busy ? null : _submit,
                child: BusyLabel(busy: _busy, label: l.recoverSubmit),
              ),
              links: [
                TextButton(
                  key: const Key('recover-back'),
                  onPressed: () => setState(() {
                    _problem = null;
                    _step = 1;
                  }),
                  child: Text(l.recoverBack),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
