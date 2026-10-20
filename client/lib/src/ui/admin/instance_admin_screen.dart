// SPDX-License-Identifier: Apache-2.0
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
import '../describe_error.dart';
import '../orgs/invite_dialog.dart';
import '../orgs/org_settings_screen.dart';

/// Binary units, rounded down: 2097152 → "2 MB".
String sizeLabel(AppLocalizations l, int bytes) => switch (bytes) {
  >= 1 << 30 => l.sizeGb(bytes >> 30),
  >= 1 << 20 => l.sizeMb(bytes >> 20),
  _ => l.sizeKb(bytes >> 10),
};

/// Accounts, invitations and organisations of the instance, for its owner; Réglages › Serveur.
class InstanceAdminPanel extends StatefulWidget {
  const InstanceAdminPanel({super.key});

  @override
  State<InstanceAdminPanel> createState() => _InstanceAdminPanelState();
}

class _InstanceAdminPanelState extends State<InstanceAdminPanel> {
  List<AdminUser> _users = const [];
  List<AdminOrg> _orgs = const [];
  List<PendingInvite> _invites = const [];
  InviteCreated? _created;
  final _email = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() => _run(() async {
    final api = AppScope.read(context).api!;
    final (users, orgs, invites) = await (
      api.adminUsers(),
      api.adminOrgs(),
      api.adminInvites(),
    ).wait;
    if (mounted) {
      setState(() {
        _users = users..sort((a, b) => a.email.compareTo(b.email));
        _orgs = orgs..sort((a, b) => a.name.compareTo(b.name));
        _invites = invites;
      });
    }
  });

  /// Errors land in the screen; lists are updated in place, never fetched again.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = describeError(AppLocalizations.of(context), e));
      }
    }
  }

  Future<void> _toggle(AdminUser u) => _run(() async {
    await AppScope.read(context).api!.adminSetDisabled(u.id, !u.disabled);
    setState(() {
      _users = [
        for (final x in _users)
          x.id == u.id
              ? AdminUser(
                  x.id,
                  x.email,
                  !x.disabled,
                  x.isInstanceOwner,
                  x.createdAt,
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
    await _run(() async {
      await api.adminDeleteUser(u.id);
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
    await _run(() async {
      await api.adminDeleteOrg(o.id, o.name);
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
    if (email.isEmpty) return setState(() => _error = l.fieldRequired);
    await _run(() async {
      final created = await api.adminInvite(email);
      final invites = await api.adminInvites();
      setState(() {
        _created = created;
        _invites = invites;
      });
    });
  }

  Future<void> _revoke(PendingInvite p) => _run(() async {
    await AppScope.read(context).api!.revokeInvite(p.id);
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
    final colors = UfColors.of(context);
    final dates = MaterialLocalizations.of(context);
    final created = _created;
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
          if (_error case final error?) UfErrorLine(error),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  children: [
                    for (final u in _users)
                      ItemRow(
                        icon: UfIcons.user,
                        title: u.email,
                        trailing: [
                          if (!u.isInstanceOwner) ...[
                            TextButton(
                              key: Key('admin-user-disable-${u.id}'),
                              style: smallButton,
                              onPressed: () => _toggle(u),
                              child: Text(
                                u.disabled ? l.adminEnable : l.adminDisable,
                              ),
                            ),
                            TextButton(
                              key: Key('admin-user-delete-${u.id}'),
                              style: dangerQuietStyle(colors)
                                  .merge(smallButton),
                              onPressed: () => _deleteUser(u),
                              child: Text(l.adminDelete),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
                ListView(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: 8,
                      children: [
                        Expanded(
                          child: UfField(
                            label: l.inviteEmail,
                            child: TextField(
                              key: const Key('admin-invite-email'),
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ),
                        FilledButton(
                          key: const Key('admin-invite-create'),
                          onPressed: _invite,
                          child: Text(l.inviteCreate),
                        ),
                      ],
                    ),
                    if (created != null) InviteResult(created: created),
                    for (final p in _invites)
                      PendingInviteRow(invite: p, onRevoke: () => _revoke(p)),
                  ],
                ),
                ListView(
                  children: [
                    for (final o in _orgs)
                      ItemRow(
                        icon: UfIcons.usersThree,
                        title: o.name,
                        subtitle: [
                          o.owners.join(', '),
                          l.adminOrgMembers(o.memberCount),
                          o.lastActivityAt == null
                              ? '—'
                              : dates.formatMediumDate(
                                  o.lastActivityAt!.toLocal(),
                                ),
                        ].join(' · '),
                        trailing: [
                          UfTag(sizeLabel(l, o.storageBytes)),
                          TextButton(
                            key: Key('admin-org-delete-${o.id}'),
                            style: dangerQuietStyle(colors).merge(smallButton),
                            onPressed: () => _deleteOrg(o),
                            child: Text(l.adminOrgDelete),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
