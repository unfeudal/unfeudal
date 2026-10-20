// SPDX-License-Identifier: Apache-2.0
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../busy_action.dart';
import '../fields.dart';

/// An existing account joins an org from an invitation link or file of its own server.
class JoinOrgDialog extends StatefulWidget {
  const JoinOrgDialog({super.key, this.openFile});

  /// The invitation file's text; a native "Open" dialog by default.
  final Future<String?> Function()? openFile;

  @override
  State<JoinOrgDialog> createState() => _JoinOrgDialogState();
}

class _JoinOrgDialogState extends State<JoinOrgDialog> with BusyAction {
  final _link = TextEditingController();
  String? _file;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final text = await (widget.openFile ?? _openFileDialog)();
    if (text != null && mounted) setState(() => _file = text);
  }

  static Future<String?> _openFileDialog() async =>
      (await openFile())?.readAsString();

  Future<void> _join() => run(() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final Enrollment invite;
    try {
      final file = _file;
      invite = file == null
          ? Enrollment.parseLink(_link.text.trim())
          : await state.parseEnrollmentFile(file);
    } on Exception {
      return setState(() => problem = l.joinInvalid);
    }
    if (invite.kind != EnrollKind.invite ||
        invite.server != state.stored?.serverUrl) {
      return setState(() => problem = l.joinInvalid);
    }
    final orgId = await state.api!.joinInvite(invite.token);
    await state.sync!.syncNow();
    state.orgs!.select(orgId);
    if (mounted) Navigator.of(context).pop();
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return UfDialog(
      title: l.railJoinOrg,
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).pop()),
        BusyButton(
          key: const Key('join-submit'),
          busy: busy,
          onPressed: _join,
          label: l.orgJoinSubmit,
        ),
      ],
      children: [
        keyedField(
          'join-link',
          _link,
          l.joinPaste,
          autofocus: true,
          onSubmitted: (_) => _join(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('join-file'),
            onPressed: _pickFile,
            child: Text(l.joinOpenFile),
          ),
        ),
        if (problem case final error?) UfErrorLine(error),
      ],
    );
  }
}
