// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/admin_models.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../manage_frame.dart';
import 'acl_editor.dart';
import 'invite_dialog.dart';
import 'members_screen.dart';
import 'org_settings_screen.dart';
import 'rotation_banner.dart';
import 'teams_screen.dart';
import 'why_rights_view.dart';

enum MembersGroup { members, invitations, teams, folders, organization }

/// Membres et accès of an org vault: a group list beside members, invitations, teams, folder access and the
/// org's settings; folder keys waiting to rotate stay announced above every group.
class MembersSection extends StatefulWidget {
  const MembersSection({super.key, required this.orgId, this.onBack});

  final String orgId;
  final VoidCallback? onBack;

  @override
  State<MembersSection> createState() => _MembersSectionState();
}

class _MembersSectionState extends State<MembersSection> {
  MembersGroup _group = MembersGroup.members;

  /// Bumped after an invitation is created, so the pending list reloads.
  int _invites = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final orgs = state.orgs!;
    final org = orgs.byId(widget.orgId);
    final isAdmin = orgs.isAdmin(widget.orgId);
    final groups = [
      (MembersGroup.members, l.membersTitle),
      if (isAdmin) (MembersGroup.invitations, l.adminInvites),
      if (isAdmin && state.serverHas('teams'))
        (MembersGroup.teams, l.teamsTitle),
      (MembersGroup.folders, l.membersGroupFolders),
      (MembersGroup.organization, l.orgMenu),
    ];
    final group = groups.any((g) => g.$1 == _group)
        ? _group
        : MembersGroup.members;
    return ManageFrame(
      title: l.sectionMembers,
      subtitle: org?.name,
      onBack: widget.onBack,
      actions: [
        if (isAdmin)
          FilledButton.icon(
            key: const Key('members-invite'),
            icon: const Icon(UfIcons.userPlus),
            onPressed: () async {
              await showUfDialog<void>(
                context,
                (_) => InviteDialog(orgId: widget.orgId),
              );
              if (mounted) setState(() => _invites++);
            },
            label: Text(l.inviteTitle),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (RotationBanner.shows(state)) const RotationBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 32,
              children: [
                GroupNav(
                  groups: groups,
                  current: group,
                  onPick: (g) => setState(() => _group = g),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: switch (group) {
                        MembersGroup.members => MembersScreen(
                          orgId: widget.orgId,
                        ),
                        MembersGroup.invitations => PendingInvites(
                          key: ValueKey(_invites),
                          orgId: widget.orgId,
                        ),
                        MembersGroup.teams => TeamsScreen(orgId: widget.orgId),
                        MembersGroup.folders => FolderAccessList(
                          orgId: widget.orgId,
                        ),
                        MembersGroup.organization => OrgSettingsScreen(
                          orgId: widget.orgId,
                        ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The org's pending invitations, each revocable by who may (an admin or owner invite: a confirmed owner only).
class PendingInvites extends StatefulWidget {
  const PendingInvites({super.key, required this.orgId});

  final String orgId;

  @override
  State<PendingInvites> createState() => _PendingInvitesState();
}

class _PendingInvitesState extends State<PendingInvites> {
  List<PendingInvite>? _pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pending = await AppScope.read(context).api!
          .orgInvites(widget.orgId);
      if (mounted) setState(() => _pending = pending);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(AppLocalizations.of(context), e));
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
            for (final p in _pending!)
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
    final isOwner = state.orgs!.isOwner(widget.orgId);
    final emails = {
      for (final m in state.orgs!.block?.members ?? const <OrgMember>[])
        m.userId: m.email,
    };
    final pending = _pending;
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        if (_error case final error?)
          StatusBanner(tone: BannerTone.danger, message: error),
        if (pending != null && pending.isEmpty)
          Text(
            l.invitesEmpty,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: colors.muted),
          ),
        for (final p in pending ?? const <PendingInvite>[])
          PendingInviteRow(
            invite: p,
            creator: emails[p.createdBy],
            onRevoke: p.role == OrgRole.member || isOwner
                ? () => _revoke(p)
                : null,
          ),
      ],
    );
  }
}

/// The org's folders with this account's rights on each; managers edit the access, anyone asks why.
class FolderAccessList extends StatelessWidget {
  const FolderAccessList({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final orgs = state.orgs!;
    final folders = [
      for (final n in orgs.block?.folderTree ?? const <FolderNode>[])
        if (n.orgId == orgId)
          (id: n.folderId, name: state.vault?.entry(n.folderId)?.name ?? ''),
    ]..sort((a, b) => a.name.compareTo(b.name));
    if (folders.isEmpty) {
      return Text(
        l.folderAccessEmpty,
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(color: colors.muted),
      );
    }
    Widget row(({String id, String name}) f) {
      final (:access, :why) = orgFolderAccessActions(context, orgId, f.id);
      return ItemRow(
        key: Key('members-folder-${f.id}'),
        icon: UfIcons.folderSimple,
        title: f.name,
        subtitle: switch (orgs.permissions(orgId, f.id)) {
          final rights when rights.isEmpty => l.whyNone,
          final rights => permissionList(l, rights),
        },
        trailing: [
          if (access != null)
            OutlinedButton(
              key: Key('members-folder-access-${f.id}'),
              style: smallButton,
              onPressed: access,
              child: Text(l.aclTitle(f.name)),
            ),
          TextButton(
            key: Key('members-folder-why-${f.id}'),
            style: smallButton,
            onPressed: why,
            child: Text(l.whyTitle),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [for (final f in folders) row(f)],
    );
  }
}
