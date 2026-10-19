// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/banner.dart';
import '../../session/lock_machine.dart';
import '../describe_error.dart';
import '../fields.dart';
import '../onboarding/recovery_screen.dart';
import 'lock_frame.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _server;
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _busy = false;
  Object? _error;
  double _eyeX = 0.5;

  @override
  void initState() {
    super.initState();
    final stored = AppScope.read(context).stored;
    _server = TextEditingController(text: stored?.serverUrl.toString());
    _email = TextEditingController(text: stored?.email);
    for (final c in [_email, _password]) {
      c.addListener(() => _typed(c));
    }
  }

  LockMachine get _machine => AppScope.read(context).lockMachine;

  void _typed(TextEditingController field) {
    _machine.input();
    setState(() => _eyeX = (field.text.length / 30).clamp(0, 1));
  }

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final machine = _machine..submit();
    try {
      await AppScope.read(context).login(
        server: Uri.parse(_server.text.trim()),
        email: _email.text.trim(),
        password: _password.text,
      );
      machine.succeed();
    } on Exception catch (e) {
      machine.fail();
      if (mounted) {
        setState(() {
          _error = e;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    return Scaffold(
      body: LockFrame(
        title: l.loginTitle,
        subtitle: state.stored?.serverUrl.host,
        eyeX: _eyeX,
        children: [
          if (state.deviceRevoked)
            StatusBanner(tone: BannerTone.danger, message: l.loginDeviceRevoked)
          else if (state.sessionExpired)
            StatusBanner(tone: BannerTone.warn, message: l.loginSessionExpired),
          keyedField(
            'login-server',
            _server,
            l.loginServer,
            keyboard: TextInputType.url,
          ),
          Focus(
            onFocusChange: (on) {
              if (on) _machine.focusEmail();
            },
            child: keyedField(
              'login-email',
              _email,
              l.loginEmail,
              keyboard: TextInputType.emailAddress,
            ),
          ),
          Focus(
            onFocusChange: (on) {
              if (on) _machine.focusPassword();
            },
            child: keyedField(
              'login-password',
              _password,
              l.loginPassword,
              secret: true,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_error case final error?) LockError(describeError(l, error)),
          LockActions(
            primary: FilledButton(
              key: const Key('login-submit'),
              onPressed: _busy ? null : _submit,
              child: BusyLabel(busy: _busy, label: l.loginSubmit),
            ),
            links: [
              TextButton(
                onPressed: () => state.show(AppStage.setup),
                child: Text(l.loginToSetup),
              ),
              TextButton(
                onPressed: () => state.show(AppStage.join),
                child: Text(l.loginToJoin),
              ),
              // shown unless the last known answer of this server says the recovery kit is off
              if (state.stored == null || state.serverHas('recovery_kit'))
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecoveryScreen(),
                    ),
                  ),
                  child: Text(l.loginToRecover),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
