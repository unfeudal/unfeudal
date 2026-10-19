// SPDX-License-Identifier: Apache-2.0
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/icons.dart';
import '../describe_error.dart';
import '../fields.dart';
import '../lock/lock_frame.dart';
import 'setup_screen.dart';

/// Joins from a link or an enrollment file: a setup enrollment prefills setup, an invite creates the account here.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.openFile});

  /// The enrollment file's text; a native "Open" dialog by default.
  final Future<String?> Function()? openFile;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _link = TextEditingController();
  final _passphrase = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _file;
  Enrollment? _invite;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    for (final c in [_link, _passphrase, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final text = await (widget.openFile ?? _openFileDialog)();
    if (text != null && mounted) setState(() => _file = text);
  }

  static Future<String?> _openFileDialog() async =>
      (await openFile())?.readAsString();

  Future<void> _submit() => _run(() async {
    final state = AppScope.read(context);
    final file = _file;
    final enrollment = file == null
        ? Enrollment.parseLink(_link.text.trim())
        : await Enrollment.parseFile(
            file,
            passphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
            allowTestingKdf: state.allowTestingKdf,
          );
    await state.checkServer(enrollment.server);
    if (enrollment.kind == EnrollKind.setup) {
      state
        ..enrollment = enrollment
        ..show(AppStage.setup);
    } else if (mounted) {
      setState(() => _invite = enrollment);
    }
  });

  Future<void> _accept() async {
    final l = AppLocalizations.of(context);
    final local = checkNewPassword(l, _password.text, _confirm.text);
    if (local != null) return setState(() => _problem = local);
    await _run(() async {
      final state = AppScope.read(context);
      await state.acceptInvite(
        enrollment: _invite!,
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!state.serverHas('recovery_kit')) state.finishOnboarding();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final invite = _invite;
    return Scaffold(
      body: LockFrame(
        step: l.stepOf(invite == null ? 1 : 2, 2),
        title: l.joinTitle,
        subtitle: invite == null
            ? l.joinSubtitle
            : l.joinInviteSubtitle(invite.server.host),
        children: [
          if (invite == null) ...[
            keyedField(
              'join-link',
              _link,
              l.joinLink,
              mono: true,
              hint: 'unfeudal://enroll?…',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('join-open-file'),
                onPressed: _pickFile,
                icon: const Icon(UfIcons.fileArrowUp, size: 16),
                label: Text(l.joinOpenFile),
              ),
            ),
            keyedField(
              'join-passphrase',
              _passphrase,
              l.joinPassphrase,
              secret: true,
            ),
          ] else ...[
            keyedField(
              'join-email',
              _email,
              l.setupEmail,
              keyboard: TextInputType.emailAddress,
            ),
            keyedField(
              'join-password',
              _password,
              l.setupPassword,
              secret: true,
            ),
            keyedField('join-confirm', _confirm, l.setupConfirm, secret: true),
            LockNotice(l.setupWarning),
          ],
          if (_problem case final problem?) LockError(problem),
          LockActions(
            primary: FilledButton(
              key: Key(invite == null ? 'join-submit' : 'join-accept'),
              onPressed: _busy ? null : (invite == null ? _submit : _accept),
              child: BusyLabel(
                busy: _busy,
                label: invite == null ? l.joinSubmit : l.setupSubmit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
