// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/admin_models.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import '../fields.dart';
import '../orgs/invite_dialog.dart';
import '../orgs/org_settings_screen.dart';

/// Binary units, rounded down: 2097152 is "2 MB".
String sizeLabel(AppLocalizations l, int bytes) => switch (bytes) {
  >= 1 << 30 => l.sizeGb(bytes >> 30),
  >= 1 << 20 => l.sizeMb(bytes >> 20),
  _ => l.sizeKb(bytes >> 10),
};

/// Accounts, invitations and organisations of the instance, for its owner; the Server group of Settings.
class InstanceAdminPanel extends StatefulWidget {
  const InstanceAdminPanel({super.key});

  @override
  State<InstanceAdminPanel> createState() => _InstanceAdminPanelState();
}

class _InstanceAdminPanelState extends State<InstanceAdminPanel>
    with BusyAction {
  List<AdminUser> _users = const [];
  List<AdminOrg> _orgs = const [];
  List<PendingInvite> _invites = const [];
  InviteCreated? _created;
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() => run(() async {
    final api = AppScope.read(context).api!;
    final (users, orgs, invites) = await (
      api.admin.users(),
      api.admin.orgs(),
      api.admin.invites(),
    ).wait;
    if (mounted) {
      setState(() {
        _users = users..sort((a, b) => a.email.compareTo(b.email));
        _orgs = orgs..sort((a, b) => a.name.compareTo(b.name));
        _invites = invites;
      });
    }
  });

  Future<void> _toggleDisabled(AdminUser u) => run(() async {
    await AppScope.read(context).api!.admin
        .setDisabled(u.id, disabled: !u.disabled);
    setState(() {
      _users = [
        for (final x in _users)
          x.id == u.id
              ? AdminUser(
                  id: x.id,
                  email: x.email,
                  disabled: !x.disabled,
                  isInstanceOwner: x.isInstanceOwner,
                  createdAt: x.createdAt,
                )
              : x,
      ];
    });
  });

  Future<void> _deleteUser(AdminUser u) async {
    final l = AppLocalizations.of(context);
    final api = AppScope.read(context).api!;
    if (!await confirmDanger(
      context,
      question: l.adminDeleteConfirm(u.email),
      action: l.adminDelete,
    )) {
      return;
    }
    await run(() async {
      await api.admin.deleteUser(u.id);
      setState(
        () => _users = [
          for (final x in _users)
            if (x.id != u.id) x,
        ],
      );
    });
  }

  Future<void> _deleteOrg(AdminOrg o) async {
    final l = AppLocalizations.of(context);
    final api = AppScope.read(context).api!;
    final yes = await showUfDialog<bool>(
      context,
      alert: true,
      (_) => ConfirmNameDialog(
        name: o.name,
        title: l.adminOrgDelete,
        fieldKey: const Key('admin-org-confirm-name'),
        okKey: const Key('admin-org-delete-ok'),
      ),
    );
    if (yes != true) return;
    await run(() async {
      await api.admin.deleteOrg(o.id, o.name);
      setState(
        () => _orgs = [
          for (final x in _orgs)
            if (x.id != o.id) x,
        ],
      );
    });
  }

  Future<void> _invite() async {
    final l = AppLocalizations.of(context);
    final api = AppScope.read(context).api!;
    final email = _email.text.trim();
    if (email.isEmpty) return setState(() => problem = l.fieldRequired);
    await run(() async {
      final created = await api.admin.invite(email);
      final invites = await api.admin.invites();
      setState(() {
        _created = created;
        _invites = invites;
      });
    });
  }

  Future<void> _revoke(PendingInvite p) => run(() async {
    await AppScope.read(context).api!.orgs.revokeInvite(p.id);
    setState(
      () => _invites = [
        for (final x in _invites)
          if (x.id != p.id) x,
      ],
    );
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: const Key('admin-tab-accounts'), text: l.adminAccounts),
              Tab(key: const Key('admin-tab-invites'), text: l.adminInvites),
              Tab(key: const Key('admin-tab-orgs'), text: l.adminOrgs),
            ],
          ),
          if (problem case final error?) UfErrorLine(error),
          Expanded(
            child: TabBarView(
              children: [
                _AccountsTab(
                  users: _users,
                  onToggleDisabled: _toggleDisabled,
                  onDelete: _deleteUser,
                ),
                _InvitesTab(
                  email: _email,
                  created: _created,
                  invites: _invites,
                  onInvite: _invite,
                  onRevoke: _revoke,
                ),
                _OrgsTab(orgs: _orgs, onDelete: _deleteOrg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab({
    required this.users,
    required this.onToggleDisabled,
    required this.onDelete,
  });

  final List<AdminUser> users;
  final ValueChanged<AdminUser> onToggleDisabled;
  final ValueChanged<AdminUser> onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return ListView(
      children: [
        for (final u in users)
          ItemRow(
            icon: UfIcons.user,
            title: u.email,
            trailing: [
              if (!u.isInstanceOwner) ...[
                TextButton(
                  key: Key('admin-user-disable-${u.id}'),
                  style: smallButton,
                  onPressed: () => onToggleDisabled(u),
                  child: Text(u.disabled ? l.adminEnable : l.adminDisable),
                ),
                TextButton(
                  key: Key('admin-user-delete-${u.id}'),
                  style: dangerQuietStyle(colors).merge(smallButton),
                  onPressed: () => onDelete(u),
                  child: Text(l.adminDelete),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _InvitesTab extends StatelessWidget {
  const _InvitesTab({
    required this.email,
    required this.created,
    required this.invites,
    required this.onInvite,
    required this.onRevoke,
  });

  final TextEditingController email;
  final InviteCreated? created;
  final List<PendingInvite> invites;
  final VoidCallback onInvite;
  final ValueChanged<PendingInvite> onRevoke;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final created = this.created;
    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 8,
          children: [
            Expanded(
              child: keyedField(
                'admin-invite-email',
                email,
                l.inviteEmail,
                keyboard: TextInputType.emailAddress,
              ),
            ),
            FilledButton(
              key: const Key('admin-invite-create'),
              onPressed: onInvite,
              child: Text(l.inviteCreate),
            ),
          ],
        ),
        if (created != null) InviteResult(created: created),
        for (final p in invites)
          PendingInviteRow(invite: p, onRevoke: () => onRevoke(p)),
      ],
    );
  }
}

class _OrgsTab extends StatelessWidget {
  const _OrgsTab({required this.orgs, required this.onDelete});

  final List<AdminOrg> orgs;
  final ValueChanged<AdminOrg> onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final dates = MaterialLocalizations.of(context);
    return ListView(
      children: [
        for (final o in orgs)
          ItemRow(
            icon: UfIcons.usersThree,
            title: o.name,
            subtitle: [
              o.owners.join(', '),
              l.adminOrgMembers(o.memberCount),
              o.lastActivityAt == null
                  ? noValue
                  : dates.formatMediumDate(o.lastActivityAt!.toLocal()),
            ].join(l.listSeparator),
            trailing: [
              UfTag(sizeLabel(l, o.storageBytes)),
              TextButton(
                key: Key('admin-org-delete-${o.id}'),
                style: dangerQuietStyle(colors).merge(smallButton),
                onPressed: () => onDelete(o),
                child: Text(l.adminOrgDelete),
              ),
            ],
          ),
      ],
    );
  }
}
