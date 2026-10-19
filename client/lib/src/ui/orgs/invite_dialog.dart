// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/admin_models.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import 'members_screen.dart';

/// Invites someone to the org: the link and file are shown once; pending invitations can be revoked.
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
  List<PendingInvite> _pending = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _loadPending() async {
    try {
      final pending = await AppScope.read(context).api!
          .orgInvites(widget.orgId);
      if (mounted) setState(() => _pending = pending);
    } on Exception catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(() => _error = describeError(l, e));
    }
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
      await _loadPending();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The list is updated here, not fetched again.
  Future<void> _revoke(PendingInvite invite) async {
    final l = AppLocalizations.of(context);
    try {
      await AppScope.read(context).api!.revokeInvite(invite.id);
      if (mounted) {
        setState(
          () => _pending = [
            for (final p in _pending)
              if (p.id != invite.id) p,
          ],
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
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
    final emails = {
      for (final m in state.orgs?.block?.members ?? const <OrgMember>[])
        m.userId: m.email,
    };
    final created = _created;
    return UfDialog(
      title: l.inviteTitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('invite-create'),
          onPressed: _busy ? null : _create,
          child: Text(l.inviteCreate),
        ),
      ],
      children: [
        TextField(
          key: const Key('invite-email'),
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: l.inviteEmail),
        ),
        DropdownButtonFormField<OrgRole>(
          key: const Key('invite-role'),
          initialValue: _role,
          decoration: InputDecoration(labelText: l.inviteRole),
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
        if (_error case final error?)
          Text(error, style: TextStyle(color: colors.danger)),
        if (created != null)
          InviteResult(created: created, saveLocation: widget.saveLocation),
        if (_pending.isNotEmpty) ...[
          Text(l.invitePending, style: Theme.of(context).textTheme.titleSmall),
          for (final p in _pending)
            PendingInviteRow(
              invite: p,
              creator: emails[p.createdBy],
              // an admin or owner invite is revoked by a confirmed owner only
              onRevoke: p.role == OrgRole.member || isOwner
                  ? () => _revoke(p)
                  : null,
            ),
        ],
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
        Text(created.link, style: monoStyle.copyWith(fontSize: 12)),
        Row(
          spacing: 8,
          children: [
            TextButton(
              key: const Key('invite-copy-link'),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: created.link)),
              child: Text(l.inviteCopyLink),
            ),
            TextButton(
              key: const Key('invite-save-file'),
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
    return Row(
      children: [
        Expanded(
          child: Text(
            [
              invite.email,
              if (invite.role case final role?) roleLabel(l, role),
              if (creator case final by?) l.inviteBy(by),
              dates.formatMediumDate(invite.expiresAt.toLocal()),
            ].join(' · '),
          ),
        ),
        TextButton(
          key: Key('invite-revoke-${invite.id}'),
          onPressed: onRevoke,
          child: Text(l.inviteRevoke),
        ),
      ],
    );
  }
}
