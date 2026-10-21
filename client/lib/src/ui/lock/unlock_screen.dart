// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/feedback.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../session/lock_machine.dart';
import '../busy_action.dart';
import '../onboarding/recovery_screen.dart';
import 'lock_frame.dart';

/// Driven by [LockMachine].
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> with BusyAction {
  late final AppState _state = AppScope.read(context);
  late final LockMachine _machine = _state.lockMachine;
  final _password = TextEditingController();
  final _focus = FocusNode();

  // Bumped by a refused password, to shake the field.
  int _shakes = 0;

  // A stored biometric wrap the server still allows.
  late final Future<bool> _biometric = _biometricEnabled();

  Future<bool> _biometricEnabled() async =>
      await _state.biometrics?.isOffered() ?? false;

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

  void _onMachine() => setState(() {});

  // The key derivation takes seconds: one at a time, the button waits for it.
  Future<void> _submit() => run(() async {
    _machine.submit();
    await _state.unlock(_password.text);
    _machine.succeed();
  });

  @override
  void failed(Object error) {
    // AppState already failed the machine on a wrong password; this covers the rest.
    _machine.fail();
    setState(() => _shakes++);
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
            _AccountChip(
              key: const Key('unlock-account'),
              name: stored.displayName,
              email: stored.email,
            ),
          UfShake(
            shakes: _shakes,
            child: UfField(
              label: l.unlockPassword,
              child: TextField(
                key: const Key('unlock-password'),
                controller: _password,
                focusNode: _focus,
                obscureText: !peeking,
                readOnly: busy,
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
                    color: peeking ? UfColors.of(context).accentText : null,
                    onPressed: _machine.togglePeek,
                  ),
                ),
              ),
            ),
          ),
          if (problem case final problem?) UfErrorLine(problem),
          LockActions(
            primary: BusyButton(
              key: const Key('unlock-submit'),
              busy: busy,
              onPressed: _submit,
              label: l.unlockSubmit,
            ),
            links: _otherWaysIn(state, l),
          ),
        ],
      ),
    );
  }

  List<Widget> _otherWaysIn(AppState state, AppLocalizations l) => [
    FutureBuilder(
      future: _biometric,
      builder: (context, enabled) => enabled.data ?? false
          ? TextButton(
              key: const Key('unlock-biometric'),
              onPressed: busy ? null : _state.unlockWithBiometrics,
              child: Text(
                defaultTargetPlatform == TargetPlatform.macOS
                    ? l.unlockBiometricMac
                    : l.unlockBiometricWindows,
              ),
            )
          : const SizedBox.shrink(),
    ),
    TextButton(onPressed: _state.signOut, child: Text(l.unlockRelogin)),
    if (state.serverInfo.has(Flag.recoveryKit)) const RecoverLink(),
  ];
}

// The known account on this device, in place of an e-mail field: its initial, name and address.
class _AccountChip extends StatelessWidget {
  const _AccountChip({super.key, required this.email, this.name});

  final String email;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final label = name ?? email;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: UfRadius.card,
        border: Border.all(color: colors.line),
      ),
      child: Row(
        spacing: 10,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.neutral,
              borderRadius: UfRadius.control,
            ),
            child: Text(
              String.fromCharCode(label.runes.first).toUpperCase(),
              style: text.labelSmall,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name case final name?)
                  Text(name, style: text.labelLarge!.copyWith(fontSize: 13.5)),
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall!.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
