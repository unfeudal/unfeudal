// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../busy_action.dart';
import '../enrollment_input.dart';
import '../fields.dart';

/// An existing account joins an org from an invitation link or file of its own server.
class JoinOrgDialog extends StatefulWidget {
  const JoinOrgDialog({super.key, this.openFile});

  /// The invitation file's text; a native "Open" dialog by default.
  final Future<String?> Function()? openFile;

  @override
  State<JoinOrgDialog> createState() => _JoinOrgDialogState();
}

class _JoinOrgDialogState extends State<JoinOrgDialog>
    with BusyAction, EnrollmentInput {
  @override
  Future<String?> Function()? get openFile => widget.openFile;

  Future<void> _join() => run(() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final Enrollment invite;
    try {
      invite = await readEnrollment();
    } on Exception {
      return setState(() => problem = l.joinInvalid);
    }
    if (invite.kind != EnrollKind.invite ||
        invite.server != state.stored?.serverUrl) {
      return setState(() => problem = l.joinInvalid);
    }
    final orgId = await state.api!.orgs.joinInvite(invite.token);
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
          link,
          l.joinPaste,
          autofocus: true,
          onSubmitted: (_) => _join(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('join-file'),
            onPressed: pickFile,
            child: Text(l.joinOpenFile),
          ),
        ),
        if (problem case final error?) UfErrorLine(error),
      ],
    );
  }
}
