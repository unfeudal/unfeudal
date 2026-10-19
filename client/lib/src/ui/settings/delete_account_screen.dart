// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/api_client.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import '../manage_frame.dart';

/// Deletes the account for good: the master password and the typed account email first.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen>
    with BusyAction {
  final _password = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final email = state.stored?.email ?? '';
    if (_password.text.isEmpty ||
        _email.text.trim().toLowerCase() != email.toLowerCase()) {
      return;
    }
    await run(() async {
      try {
        await state.deleteAccount(_password.text);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } on WrongPassword {
        if (mounted) setState(() => problem = l.passwordCurrentWrong);
      } on ApiException catch (e) {
        if (e.reason != 'last_owner') rethrow;
        if (mounted) {
          setState(
            () => problem = l.deleteLastOwner((e.orgs ?? const []).join(', ')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return ManageFrame(
      title: l.settingsDeleteAccount,
      maxWidth: 520,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(l.deleteAccountBody, style: TextStyle(color: colors.danger)),
          UfField(
            label: l.deletePassword,
            child: TextField(
              key: const Key('delete-password'),
              controller: _password,
              obscureText: true,
            ),
          ),
          UfField(
            label: l.deleteConfirmEmail,
            child: TextField(
              key: const Key('delete-confirm-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          if (problem case final problem?)
            Text(problem, style: TextStyle(color: colors.danger)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('delete-submit'),
              style: dangerButtonStyle(colors),
              onPressed: busy ? null : _submit,
              child: Text(l.deleteSubmit),
            ),
          ),
        ],
      ),
    );
  }
}
