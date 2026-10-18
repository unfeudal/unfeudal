// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../session/lock_machine.dart';
import '../describe_error.dart';
import 'lock_frame.dart';

/// Driven by [LockMachine]; every state change is reported as a [LockScreenStateChanged] event.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  late final AppState _state = AppScope.read(context);
  late final LockMachine _machine = _state.lockMachine;
  final _password = TextEditingController();
  final _focus = FocusNode();
  Object? _error;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    _machine
      ..addListener(_onMachine)
      ..startIdleWatch();
    _focus.addListener(() {
      if (_focus.hasFocus) _machine.focusPassword();
    });
  }

  @override
  void dispose() {
    _machine
      ..removeListener(_onMachine)
      ..stopIdleWatch();
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onMachine() {
    _state.emit(LockScreenStateChanged(_machine.state));
    setState(() {});
  }

  Future<void> _submit() async {
    _machine.submit();
    try {
      await _state.unlock(_password.text);
      _machine.succeed();
    } on Exception catch (e) {
      _machine.fail(); // AppState already failed the machine on a wrong password; this covers the rest
      if (mounted) {
        setState(() {
          _error = e;
          _failures++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final stored = AppScope.of(context).stored;
    final peeking = _machine.state == LockScreenState.peek;
    return Scaffold(
      body: LockFrame(
        children: [
          Text(
            l.unlockTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (stored != null)
            ListTile(
              leading: const Icon(UfIcons.user),
              title: Text(stored.displayName ?? stored.email),
              subtitle: stored.displayName == null ? null : Text(stored.email),
            ),
          ShakeOnError(
            trigger: _failures,
            child: TextField(
              key: const Key('unlock-password'),
              controller: _password,
              focusNode: _focus,
              obscureText: !peeking,
              onChanged: (_) => _machine.input(),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l.unlockPassword,
                suffixIcon: IconButton(
                  key: const Key('unlock-peek'),
                  tooltip: l.unlockPeek,
                  icon: Icon(peeking ? UfIcons.eyeSlash : UfIcons.eye),
                  onPressed: _machine.togglePeek,
                ),
              ),
            ),
          ),
          if (_error case final error?)
            Text(
              describeError(l, error),
              style: TextStyle(color: UfColors.of(context).danger),
            ),
          FilledButton(
            key: const Key('unlock-submit'),
            onPressed: _submit,
            child: Text(l.unlockSubmit),
          ),
          TextButton(onPressed: _state.signOut, child: Text(l.unlockRelogin)),
        ],
      ),
    );
  }
}
