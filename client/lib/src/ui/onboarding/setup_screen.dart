// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../lock/lock_frame.dart';
import 'recovery_kit_view.dart';

/// First account of a server; once created, the recovery kit (when the server offers it) before home.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _server;
  late final TextEditingController _token;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _problem;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    final enrollment = AppScope.read(context).enrollment;
    _server = TextEditingController(text: enrollment?.server.toString());
    _token = TextEditingController(text: enrollment?.token);
  }

  @override
  void dispose() {
    for (final c in [_server, _token, _email, _password, _confirm, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final local = checkNewPassword(l, _password.text, _confirm.text);
    if (local != null) return _fail(local);
    setState(() => _busy = true);
    try {
      await state.setup(
        server: Uri.parse(_server.text.trim()),
        token: _token.text,
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      );
      if (!state.serverHas('recovery_kit')) state.finishOnboarding();
    } on Exception catch (e) {
      if (mounted) _fail(describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String problem) => setState(() {
    _problem = problem;
    _failures++;
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    if (state.recoveryKey case final key?) {
      return RecoveryKitView(recoveryKey: key, onDone: state.finishOnboarding);
    }
    return Scaffold(
      body: LockFrame(
        children: [
          Text(l.setupTitle, style: Theme.of(context).textTheme.headlineMedium),
          _field(
            'setup-server',
            _server,
            l.setupServer,
            keyboard: TextInputType.url,
          ),
          _field('setup-token', _token, l.setupToken),
          _field(
            'setup-email',
            _email,
            l.setupEmail,
            keyboard: TextInputType.emailAddress,
          ),
          ShakeOnError(
            trigger: _failures,
            child: Column(
              spacing: 12,
              children: [
                _field(
                  'setup-password',
                  _password,
                  l.setupPassword,
                  secret: true,
                ),
                _field('setup-confirm', _confirm, l.setupConfirm, secret: true),
              ],
            ),
          ),
          _field('setup-name', _name, l.setupDisplayName),
          Text(
            l.setupWarning,
            style: TextStyle(color: UfColors.of(context).warn),
          ),
          if (_problem case final problem?)
            Text(problem, style: TextStyle(color: UfColors.of(context).danger)),
          FilledButton(
            key: const Key('setup-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(l.setupSubmit),
          ),
        ],
      ),
    );
  }
}

/// Null when the new password is long enough and confirmed; else the sentence to show. Nothing is sent before.
String? checkNewPassword(
  AppLocalizations l,
  String password,
  String confirmation,
) {
  if (password.runes.length < AccountCrypto.minPasswordLength) {
    return l.errorWeakPassword(AccountCrypto.minPasswordLength);
  }
  return password == confirmation ? null : l.passwordsDiffer;
}

Widget _field(
  String key,
  TextEditingController controller,
  String label, {
  bool secret = false,
  TextInputType? keyboard,
}) => TextField(
  key: Key(key),
  controller: controller,
  obscureText: secret,
  keyboardType: keyboard,
  decoration: InputDecoration(labelText: label),
);
