// SPDX-License-Identifier: Apache-2.0
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';

/// An existing account joins an org from an invitation link or file of its own server.
class JoinOrgDialog extends StatefulWidget {
  const JoinOrgDialog({super.key, this.openFile});

  /// The invitation file's text; a native "Open" dialog by default.
  final Future<String?> Function()? openFile;

  @override
  State<JoinOrgDialog> createState() => _JoinOrgDialogState();
}

class _JoinOrgDialogState extends State<JoinOrgDialog> {
  final _link = TextEditingController();
  String? _file;
  bool _busy = false;
  String? _error;

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

  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final Enrollment invite;
    try {
      final file = _file;
      invite = file == null
          ? Enrollment.parseLink(_link.text.trim())
          : await Enrollment.parseFile(
              file,
              allowTestingKdf: state.allowTestingKdf,
            );
    } on Exception {
      return setState(() => _error = l.joinInvalid);
    }
    if (invite.kind != EnrollKind.invite ||
        invite.server != state.stored?.serverUrl) {
      return setState(() => _error = l.joinInvalid);
    }
    setState(() => _busy = true);
    try {
      final orgId = await state.api!.joinInvite(invite.token);
      await state.sync!.syncNow();
      state.orgs!.select(orgId);
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return UfDialog(
      title: l.railJoinOrg,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('join-submit'),
          onPressed: _busy ? null : _join,
          child: Text(l.orgJoinSubmit),
        ),
      ],
      children: [
        TextField(
          key: const Key('join-link'),
          controller: _link,
          autofocus: true,
          decoration: InputDecoration(labelText: l.joinPaste),
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
        if (_error case final error?)
          Text(error, style: TextStyle(color: UfColors.of(context).danger)),
      ],
    );
  }
}
