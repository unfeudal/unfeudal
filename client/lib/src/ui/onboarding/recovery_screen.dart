// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/tokens.dart';
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

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    // a mistyped key is refused before any request
    try {
      RecoveryKey.decode(_key.text);
    } on InvalidRecoveryKey catch (e) {
      return setState(() => _problem = describeError(l, e));
    }
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
    return Scaffold(
      body: LockFrame(
        children: [
          Text(
            l.recoverTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
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
          keyedField('recover-key', _key, l.recoverKey),
          keyedField(
            'recover-password',
            _password,
            l.recoverNewPassword,
            secret: true,
          ),
          keyedField('recover-confirm', _confirm, l.setupConfirm, secret: true),
          if (_problem case final problem?)
            Text(problem, style: TextStyle(color: UfColors.of(context).danger)),
          FilledButton(
            key: const Key('recover-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(l.recoverSubmit),
          ),
        ],
      ),
    );
  }
}
