// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/banner.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import 'lock_frame.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _server = TextEditingController(
    text: AppScope.read(context).stored?.serverUrl.toString(),
  );
  late final _email = TextEditingController(
    text: AppScope.read(context).stored?.email,
  );
  final _password = TextEditingController();
  bool _busy = false;
  Object? _error;
  int _failures = 0;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).login(
        server: Uri.parse(_server.text.trim()),
        email: _email.text.trim(),
        password: _password.text,
      );
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _failures++;
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
        children: [
          Text(l.loginTitle, style: Theme.of(context).textTheme.headlineMedium),
          if (state.deviceRevoked)
            StatusBanner(tone: BannerTone.danger, message: l.loginDeviceRevoked)
          else if (state.sessionExpired)
            StatusBanner(tone: BannerTone.warn, message: l.loginSessionExpired),
          TextField(
            key: const Key('login-server'),
            controller: _server,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l.loginServer),
          ),
          TextField(
            key: const Key('login-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l.loginEmail),
          ),
          ShakeOnError(
            trigger: _failures,
            child: TextField(
              key: const Key('login-password'),
              controller: _password,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: l.loginPassword),
            ),
          ),
          if (_error case final error?)
            Text(
              describeError(l, error),
              style: TextStyle(color: UfColors.of(context).danger),
            ),
          FilledButton(
            key: const Key('login-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(l.loginSubmit),
          ),
          TextButton(
            onPressed: () => state.show(AppStage.setup),
            child: Text(l.loginToSetup),
          ),
          TextButton(
            onPressed: () => state.show(AppStage.join),
            child: Text(l.loginToJoin),
          ),
        ],
      ),
    );
  }
}
