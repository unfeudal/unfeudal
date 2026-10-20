// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../busy_action.dart';
import '../fields.dart';
import '../lock/lock_frame.dart';
import 'recovery_kit_view.dart';

/// First account of a server; once created, the recovery kit (when the server offers it) before home.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with BusyAction {
  late final TextEditingController _server;
  late final TextEditingController _token;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();

  /// 1: server and token; 2: the owner account. A setup link fills step 1 and opens on step 2.
  late int _step = _token.text.isEmpty ? 1 : 2;

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

  /// Checked here, the server is only reached by the final submit (one plain-http prompt, not two).
  void _next() {
    final l = AppLocalizations.of(context);
    final server = Uri.tryParse(_server.text.trim());
    if (server == null || !server.hasScheme || server.host.isEmpty) {
      return _fail(l.fieldInvalid);
    }
    if (_token.text.trim().isEmpty) return _fail(l.fieldRequired);
    setState(() {
      problem = null;
      _step = 2;
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final local = checkNewPassword(l, _password.text, _confirm.text);
    if (local != null) return _fail(local);
    await run(() async {
      await state.setup(
        server: Uri.parse(_server.text.trim()),
        token: _token.text,
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      );
      if (!state.serverHas('recovery_kit')) state.finishOnboarding();
    });
  }

  void _fail(String text) => setState(() => problem = text);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    if (state.recoveryKey case final key?) {
      return RecoveryKitView(recoveryKey: key, onDone: state.finishOnboarding);
    }
    final first = _step == 1;
    return Scaffold(
      body: LockFrame(
        step: l.stepOf(_step, 2),
        title: first ? l.setupTitle : l.setupAccountTitle,
        subtitle: first
            ? l.setupSubtitle
            : l.setupAccountSubtitle(
                Uri.tryParse(_server.text.trim())?.host ?? '',
              ),
        children: [
          if (first) ...[
            keyedField(
              'setup-server',
              _server,
              l.setupServer,
              keyboard: TextInputType.url,
            ),
            keyedField(
              'setup-token',
              _token,
              l.setupToken,
              mono: true,
              hint: 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ',
              onSubmitted: (_) => _next(),
            ),
          ] else ...[
            keyedField(
              'setup-email',
              _email,
              l.setupEmail,
              keyboard: TextInputType.emailAddress,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                keyedField(
                  'setup-password',
                  _password,
                  l.setupPassword,
                  secret: true,
                  strength: true,
                ),
                keyedField(
                  'setup-confirm',
                  _confirm,
                  l.setupConfirm,
                  secret: true,
                ),
              ],
            ),
            keyedField('setup-name', _name, l.setupDisplayName),
            LockNotice(l.setupWarning),
          ],
          if (problem case final problem?) UfErrorLine(problem),
          if (first)
            LockActions(
              primary: FilledButton(
                key: const Key('setup-next'),
                onPressed: _next,
                child: Text(l.stepNext),
              ),
            )
          else
            LockActions(
              primary: FilledButton(
                key: const Key('setup-submit'),
                onPressed: busy ? null : _submit,
                child: BusyLabel(busy: busy, label: l.setupSubmit),
              ),
              links: [
                TextButton(
                  key: const Key('setup-back'),
                  onPressed: () => setState(() {
                    problem = null;
                    _step = 1;
                  }),
                  child: Text(l.setupBack),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String? checkNewPassword(
  AppLocalizations l,
  String password,
  String confirmation,
) {
  if (passwordLength(password) < AccountCrypto.minPasswordLength) {
    return l.errorWeakPassword(AccountCrypto.minPasswordLength);
  }
  return password == confirmation ? null : l.passwordsDiffer;
}
