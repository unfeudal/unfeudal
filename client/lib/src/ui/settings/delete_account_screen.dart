// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/api_client.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../manage_frame.dart';

/// Deletes the account for good: the master password and the typed account email first.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _problem;

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
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await state.deleteAccount(_password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on WrongPassword {
      if (mounted) setState(() => _problem = l.passwordCurrentWrong);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _problem = e.reason == 'last_owner'
            ? l.deleteLastOwner((e.orgs ?? const []).join(', '))
            : describeError(l, e),
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return ManageFrame(
      title: l.settingsDeleteAccount,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(l.deleteAccountBody, style: TextStyle(color: colors.danger)),
              TextField(
                key: const Key('delete-password'),
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: l.deletePassword),
              ),
              TextField(
                key: const Key('delete-confirm-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l.deleteConfirmEmail),
              ),
              if (_problem case final problem?)
                Text(problem, style: TextStyle(color: colors.danger)),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('delete-submit'),
                  style: dangerButtonStyle(colors),
                  onPressed: _busy ? null : _submit,
                  child: Text(l.deleteSubmit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
