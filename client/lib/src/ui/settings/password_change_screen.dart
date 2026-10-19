// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/field.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import '../manage_frame.dart';
import '../onboarding/recovery_kit_view.dart';
import '../onboarding/setup_screen.dart' show checkNewPassword;

/// Changes the master password; in [securityReset] mode a new recovery kit follows when the server allows it.
class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key, this.securityReset = false});

  final bool securityReset;

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen>
    with BusyAction {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  /// Reset mode, after the change: the new kit, or null when the server allows none.
  String? _kit;
  bool _done = false;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final local = checkNewPassword(l, _next.text, _confirm.text);
    if (local != null) return setState(() => problem = local);
    await run(() async {
      try {
        if (widget.securityReset) {
          final kit = await state.securityReset(_current.text, _next.text);
          if (mounted) {
            setState(() {
              _kit = kit;
              _done = true;
            });
          }
        } else {
          await state.changeMasterPassword(_current.text, _next.text);
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.passwordChanged)));
          Navigator.of(context).maybePop();
        }
      } on WrongPassword {
        if (mounted) {
          setState(() {
            problem = l.passwordCurrentWrong;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final kit = _kit;
    if (kit != null) {
      return RecoveryKitView(
        recoveryKey: kit,
        onDone: () => Navigator.of(context).maybePop(),
      );
    }
    Widget field(String key, TextEditingController c, String label) => UfField(
      label: label,
      child: TextField(
        key: Key(key),
        controller: c,
        obscureText: true,
        enabled: !_done,
      ),
    );
    // a Scaffold of its own: pushed alone, the confirmation still has somewhere to show
    return Scaffold(
      body: ManageFrame(
        title: widget.securityReset
            ? l.securityResetTitle
            : l.settingsChangePassword,
        maxWidth: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (widget.securityReset) Text(l.securityResetBody),
            field('pw-current', _current, l.pwCurrent),
            field('pw-next', _next, l.pwNext),
            field('pw-confirm', _confirm, l.pwConfirm),
            if (problem case final problem?)
              Text(problem, style: TextStyle(color: colors.danger)),
            if (_done)
              Text(l.securityResetNoKit)
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('pw-submit'),
                  onPressed: busy ? null : _submit,
                  child: Text(l.pwSubmit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
