// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/acl_grid.dart';
import '../../design/buttons.dart';
import '../../design/field.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import '../manage_frame.dart';

String permissionLabel(AppLocalizations l, Permission p) => switch (p) {
  Permission.view => l.permView,
  Permission.connect => l.permConnect,
  Permission.reveal => l.permReveal,
  Permission.edit => l.permEdit,
  Permission.manage => l.permManage,
};

/// Names in [Permission.values] order, joined by ", ".
String permissionList(AppLocalizations l, Set<Permission> perms) => [
  for (final p in Permission.values)
    if (perms.contains(p)) permissionLabel(l, p),
].join(', ');

/// The folder's access entries: teams only allow, members may also deny. A manager who is not an admin cannot
/// grant what they lack nor drop their own `manage`; the server decides anyway.
class AclEditor extends StatefulWidget {
  const AclEditor({super.key, required this.orgId, required this.folderId});

  final String orgId;
  final String folderId;

  @override
  State<AclEditor> createState() => _AclEditorState();
}

class _AclEditorState extends State<AclEditor> with BusyAction {
  // (type, allow, deny) by principal id, from the block's entries on this folder.
  late final Map<String, (PrincipalType, Set<Permission>, Set<Permission>)>
  _entries = _load();

  Map<String, (PrincipalType, Set<Permission>, Set<Permission>)> _load() {
    final block = AppScope.read(context).orgs!.block;
    return {
      for (final a in block?.acl ?? const <AclRow>[])
        if (a.orgId == widget.orgId && a.folderId == widget.folderId)
          a.principalId: (a.entry.principalType, a.entry.allow, a.entry.deny),
    };
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    await run(() async {
      await state.api!.orgs.putAcl(widget.folderId, [
        for (final MapEntry(key: id, value: (type, allow, deny))
            in _entries.entries)
          if (allow.isNotEmpty || deny.isNotEmpty)
            AclEntry(
              folderId: widget.folderId,
              principalType: type,
              principalId: id,
              allow: allow,
              deny: deny,
            ),
      ]);
      await state.sync!.syncNow();
    });
  }

  // One right of one principal: allow, deny (members only) or unset. A manager who is not an admin can only
  // deny what they lack, and keeps their own manage.
  Widget _toggle(
    String id,
    PrincipalType type,
    Permission p, {
    required bool isAdmin,
    required Set<Permission> held,
    required String me,
  }) {
    final l = AppLocalizations.of(context);
    final (_, allow, deny) =
        _entries[id] ?? (type, <Permission>{}, <Permission>{});
    final state = allow.contains(p)
        ? UfTriState.allow
        : deny.contains(p)
        ? UfTriState.deny
        : UfTriState.unset;
    final canDeny = type == PrincipalType.user;
    final canGrant = isAdmin || held.contains(p);
    final locked =
        !isAdmin &&
        ((id == me && p == Permission.manage) ||
            (!canGrant && !canDeny && state == UfTriState.unset));
    return UfTriToggle(
      key: Key('acl-$id-${p.name}'),
      state: state,
      canDeny: canDeny,
      semanticLabel: permissionLabel(l, p),
      onChanged: locked
          ? null
          : (next) => setState(() {
              final to = next == UfTriState.allow && !canGrant
                  ? UfTriState.deny
                  : next;
              final entry = _entries[id] ??= (
                type,
                <Permission>{},
                <Permission>{},
              );
              entry.$2.remove(p);
              entry.$3.remove(p);
              if (to == UfTriState.allow) entry.$2.add(p);
              if (to == UfTriState.deny) entry.$3.add(p);
            }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final orgs = state.orgs!;
    final me = state.stored!.userId;
    final block = orgs.block;
    final isAdmin = orgs.isAdmin(widget.orgId);
    final held = orgs.permissions(widget.orgId, widget.folderId);
    final teams = [
      if (state.serverInfo.has(Flag.teams))
        for (final t in block?.teams ?? const <OrgTeam>[])
          if (t.orgId == widget.orgId) t,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final members = state.serverInfo.has(Flag.userOverrides)
        ? orgs.membersOf(widget.orgId)
        : const <OrgMember>[];
    final folderName = state.vault?.entry(widget.folderId)?.name ?? '';

    List<Widget> row(String id, String name, PrincipalType type) => [
      Text(name, overflow: TextOverflow.ellipsis),
      for (final p in Permission.values)
        _toggle(id, type, p, isAdmin: isAdmin, held: held, me: me),
    ];

    return ManageFrame(
      title: l.aclTitle(folderName),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          UfAclGrid(
            headers: [
              l.aclWho,
              for (final p in Permission.values) permissionLabel(l, p),
            ],
            rows: [
              for (final t in teams) row(t.id, t.name, PrincipalType.team),
              for (final m in members)
                row(m.userId, m.email, PrincipalType.user),
            ],
          ),
          Text(l.aclRevealNote, style: TextStyle(color: colors.muted)),
          if (problem case final error?) UfErrorLine(error),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('acl-save'),
              busy: busy,
              onPressed: _save,
              label: l.aclSave,
            ),
          ),
        ],
      ),
    );
  }
}
