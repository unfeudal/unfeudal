// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/feedback.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../session/lock_machine.dart';
import '../describe_error.dart';
import '../onboarding/recovery_screen.dart';
import 'lock_frame.dart';

/// Driven by [LockMachine].
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

  /// Bumped by a refused password, to shake the field.
  int _shakes = 0;

  /// The key derivation takes seconds: one at a time, the button waits for it.
  bool _busy = false;

  /// A stored biometric wrap the server still allows.
  late final Future<bool> _biometric = _biometricEnabled();

  Future<bool> _biometricEnabled() async =>
      _state.serverHas('biometric_unlock') &&
      (await _state.biometric?.isEnabled() ?? false);

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
          _shakes++;
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
                    color: peeking ? UfColors.of(context).accentText : null,
                    onPressed: _machine.togglePeek,
                  ),
                ),
              ),
            ),
          ),
          if (_error case final error?) UfErrorLine(describeError(l, error)),
          LockActions(
            primary: FilledButton(
              key: const Key('unlock-submit'),
              onPressed: _busy ? null : _submit,
              child: BusyLabel(busy: _busy, label: l.unlockSubmit),
            ),
            links: [
              FutureBuilder(
                future: _biometric,
                builder: (context, enabled) => enabled.data ?? false
                    ? TextButton(
                        key: const Key('unlock-biometric'),
                        onPressed: _busy ? null : _state.unlockWithBiometrics,
                        child: Text(
                          Platform.isMacOS
                              ? l.unlockBiometricMac
                              : l.unlockBiometricWindows,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
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

/// The known account on this device, in place of an e-mail field: its initial, name and address.
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
