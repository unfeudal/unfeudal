// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/admin_models.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
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

class _InviteDialogState extends State<InviteDialog> {
  final _email = TextEditingController();
  OrgRole _role = OrgRole.member;
  InviteCreated? _created;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final api = AppScope.read(context).api!;
    final email = _email.text.trim();
    if (email.isEmpty) return setState(() => _error = l.fieldRequired);
    setState(() => _busy = true);
    try {
      final created = await api.createInvite(
        widget.orgId,
        email: email,
        role: _role,
      );
      if (mounted) {
        setState(() {
          _created = created;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final isOwner =
        state.orgs?.orgs.any(
          (o) => o.id == widget.orgId && o.role == OrgRole.owner.name,
        ) ??
        false;
    final created = _created;
    return UfDialog(
      title: l.inviteTitle,
      width: 480,
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).maybePop()),
        FilledButton(
          key: const Key('invite-create'),
          onPressed: _busy ? null : _create,
          child: Text(l.inviteCreate),
        ),
      ],
      children: [
        UfField(
          label: l.inviteEmail,
          child: TextField(
            key: const Key('invite-email'),
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        UfField(
          label: l.inviteRole,
          child: DropdownButtonFormField<OrgRole>(
            key: const Key('invite-role'),
            initialValue: _role,
            items: [
              for (final r in OrgRole.values)
                DropdownMenuItem(
                  value: r,
                  enabled: isOwner || r == OrgRole.member,
                  child: Text(roleLabel(l, r)),
                ),
            ],
            onChanged: (r) => setState(() => _role = r ?? OrgRole.member),
          ),
        ),
        if (_error case final error?)
          Text(error, style: TextStyle(color: colors.danger)),
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
    final path = await (saveLocation ?? _pickSaveLocation)(name);
    if (path != null) await File(path).writeAsString(created.file);
  }

  static Future<String?> _pickSaveLocation(String suggestedName) async =>
      (await getSaveLocation(suggestedName: suggestedName))?.path;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(created.mailSent ? l.inviteMailSent : l.inviteShare),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: UfColors.of(context).line),
            borderRadius: UfRadius.control,
          ),
          child: SelectableText(
            created.link,
            style: monoStyle.copyWith(fontSize: 12),
          ),
        ),
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
