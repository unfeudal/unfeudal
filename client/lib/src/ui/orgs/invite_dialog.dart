// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/admin_models.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/choices.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/inputs.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import '../fields.dart';
import '../save_file.dart';
import 'members_screen.dart';

/// Invites someone to the org: the link and file are shown once.
class InviteDialog extends StatefulWidget {
  const InviteDialog({super.key, required this.orgId, this.saveLocation});

  final String orgId;

  /// Where to save the invitation file; a native "Save" dialog by default.
  final Future<String?> Function(String suggestedName)? saveLocation;

  @override
  State<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<InviteDialog> with BusyAction {
  final _email = TextEditingController();
  OrgRole _role = OrgRole.member;
  InviteCreated? _created;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final api = AppScope.read(context).api!;
    final email = _email.text.trim();
    if (email.isEmpty) return setState(() => problem = l.fieldRequired);
    await run(() async {
      final created = await api.createInvite(
        widget.orgId,
        email: email,
        role: _role,
      );
      if (mounted) setState(() => _created = created);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final isOwner = state.orgs?.isOwner(widget.orgId) ?? false;
    final created = _created;
    return UfDialog(
      title: l.inviteTitle,
      width: 480,
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).maybePop()),
        BusyButton(
          key: const Key('invite-create'),
          busy: busy,
          onPressed: _create,
          label: l.inviteCreate,
        ),
      ],
      children: [
        keyedField(
          'invite-email',
          _email,
          l.inviteEmail,
          autofocus: true,
          keyboard: TextInputType.emailAddress,
        ),
        UfField(
          label: l.inviteRole,
          child: UfSelect<OrgRole>(
            key: const Key('invite-role'),
            value: _role,
            options: [
              for (final r in OrgRole.values)
                UfOption(
                  r,
                  roleLabel(l, r),
                  enabled: isOwner || r == OrgRole.member,
                ),
            ],
            onChanged: (r) => setState(() => _role = r),
          ),
        ),
        if (problem case final error?) UfErrorLine(error),
        if (created != null)
          InviteResult(created: created, saveLocation: widget.saveLocation),
      ],
    );
  }
}

/// A new invitation, shown once: whether a mail left, the link to copy and the file to save.
class InviteResult extends StatelessWidget {
  const InviteResult({super.key, required this.created, this.saveLocation});

  final InviteCreated created;

  /// Where to save the invitation file; a native "Save" dialog by default.
  final Future<String?> Function(String suggestedName)? saveLocation;

  Future<void> _saveFile() async {
    const name = 'unfeudal-invite.unfeudal-enroll';
    final path = await (saveLocation ?? pickSaveLocation)(name);
    if (path != null) await writeFileBytes(path, utf8.encode(created.file));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(created.mailSent ? l.inviteMailSent : l.inviteShare),
        UfReadOnlyField(value: created.link),
        Row(
          spacing: 8,
          children: [
            OutlinedButton(
              key: const Key('invite-copy-link'),
              style: smallButton,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: created.link)),
              child: Text(l.inviteCopyLink),
            ),
            OutlinedButton(
              key: const Key('invite-save-file'),
              style: smallButton,
              onPressed: _saveFile,
              child: Text(l.inviteSaveFile),
            ),
          ],
        ),
      ],
    );
  }
}

/// A pending invitation: email, expiry and revoke.
class PendingInviteRow extends StatelessWidget {
  const PendingInviteRow({
    super.key,
    required this.invite,
    required this.onRevoke,
    this.creator,
  });

  final PendingInvite invite;

  /// Null disables the button: this user may not revoke it.
  final VoidCallback? onRevoke;

  /// The email of who sent it, when known.
  final String? creator;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    return ItemRow(
      icon: UfIcons.envelope,
      title: [
        invite.email,
        if (invite.role case final role?) roleLabel(l, role),
        if (creator case final by?) l.inviteBy(by),
      ].join(' · '),
      subtitle: dates.formatMediumDate(invite.expiresAt.toLocal()),
      trailing: [
        TextButton(
          key: Key('invite-revoke-${invite.id}'),
          style: dangerQuietStyle(UfColors.of(context)).merge(smallButton),
          onPressed: onRevoke,
          child: Text(l.inviteRevoke),
        ),
      ],
    );
  }
}
