// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/api_client.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/field.dart';
import '../../design/feedback.dart';
import '../../design/buttons.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import '../fields.dart';
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
        if (e.conflictReason != ConflictReason.lastOwner) rethrow;
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
          UfNotice(tone: BannerTone.danger, message: l.deleteAccountBody),
          keyedField(
            'delete-password',
            _password,
            l.deletePassword,
            secret: true,
          ),
          keyedField(
            'delete-confirm-email',
            _email,
            l.deleteConfirmEmail,
            keyboard: TextInputType.emailAddress,
          ),
          if (problem case final problem?) UfErrorLine(problem),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('delete-submit'),
              style: dangerButtonStyle(colors),
              busy: busy,
              onPressed: _submit,
              label: l.deleteSubmit,
            ),
          ),
        ],
      ),
    );
  }
}
