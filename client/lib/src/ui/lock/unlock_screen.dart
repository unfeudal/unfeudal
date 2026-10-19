// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../session/lock_machine.dart';
import '../describe_error.dart';
import '../onboarding/recovery_screen.dart';
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

  /// The key derivation takes seconds: one at a time, the button waits for it.
  bool _busy = false;
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
    if (_busy) return;
    setState(() => _busy = true);
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final stored = state.stored;
    final peeking = _machine.state == LockScreenState.peek;
    return Scaffold(
      body: LockFrame(
        title: l.unlockTitle,
        subtitle: stored?.serverUrl.host,
        eyeX: (_password.text.length / 30).clamp(0, 1),
        children: [
          if (stored != null)
            UfField(
              label: l.loginEmail,
              child: TextFormField(
                key: const Key('unlock-account'),
                initialValue: stored.email,
                readOnly: true,
                enableInteractiveSelection: false,
                decoration: InputDecoration(helperText: stored.displayName),
              ),
            ),
          ShakeOnError(
            trigger: _failures,
            child: UfField(
              label: l.unlockPassword,
              child: TextField(
                key: const Key('unlock-password'),
                controller: _password,
                focusNode: _focus,
                obscureText: !peeking,
                readOnly: _busy,
                onChanged: (_) {
                  _machine.input();
                  setState(() {});
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    key: const Key('unlock-peek'),
                    tooltip: l.unlockPeek,
                    icon: Icon(peeking ? UfIcons.eyeSlash : UfIcons.eye),
                    color: peeking ? UfColors.of(context).accent : null,
                    onPressed: _machine.togglePeek,
                  ),
                ),
              ),
            ),
          ),
          if (_error case final error?) LockError(describeError(l, error)),
          LockActions(
            primary: FilledButton(
              key: const Key('unlock-submit'),
              onPressed: _busy ? null : _submit,
              child: BusyLabel(busy: _busy, label: l.unlockSubmit),
            ),
            links: [
              TextButton(
                onPressed: _state.signOut,
                child: Text(l.unlockRelogin),
              ),
              if (state.serverHas('recovery_kit'))
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
