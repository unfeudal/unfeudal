// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
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
  const AclEditor({
    super.key,
    required this.orgId,
    required this.folderId,
    this.onBack,
  });

  final String orgId;
  final String folderId;
  final VoidCallback? onBack;

  @override
  State<AclEditor> createState() => _AclEditorState();
}

class _AclEditorState extends State<AclEditor> {
  /// principal id → (type, allow, deny), from the block's entries on this folder.
  late final Map<String, (PrincipalType, Set<Permission>, Set<Permission>)>
  _entries = _load();
  bool _busy = false;
  String? _error;

  Map<String, (PrincipalType, Set<Permission>, Set<Permission>)> _load() {
    final block = AppScope.read(context).orgs!.block;
    Set<Permission> perms(List<String> names) => {
      for (final n in names) ...Permission.values.where((p) => p.name == n),
    };
    return {
      for (final a in block?.acl ?? const <AclRow>[])
        if (a.orgId == widget.orgId && a.folderId == widget.folderId)
          a.principalId: (
            a.principalType == 'team' ? PrincipalType.team : PrincipalType.user,
            perms(a.allow),
            perms(a.deny),
          ),
    };
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await state.api!.putAcl(widget.folderId, [
        for (final MapEntry(key: id, value: (type, allow, deny))
            in _entries.entries)
          if (allow.isNotEmpty || deny.isNotEmpty)
            AclEntry(widget.folderId, type, id, allow, deny),
      ]);
      await state.sync!.syncNow();
      if (mounted) setState(() => _error = null);
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
    final orgs = state.orgs!;
    final me = state.stored!.userId;
    final block = orgs.block;
    final isAdmin = orgs.isAdmin(widget.orgId);
    final held = orgs.permissions(widget.orgId, widget.folderId);
    final teams = [
      if (state.serverHas('teams'))
        for (final t in block?.teams ?? const <OrgTeam>[])
          if (t.orgId == widget.orgId) t,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final members = [
      if (state.serverHas('user_overrides'))
        for (final m in block?.members ?? const <OrgMember>[])
          if (m.orgId == widget.orgId) m,
    ]..sort((a, b) => a.email.compareTo(b.email));
    final folderName = state.vault?.entry(widget.folderId)?.name ?? '';

    Widget chips(String id, PrincipalType type, {required bool deny}) {
      final (_, allow, denied) =
          _entries[id] ?? (type, <Permission>{}, <Permission>{});
      final set = deny ? denied : allow;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in Permission.values)
            FilterChip(
              key: Key('acl-$id-${deny ? 'deny' : 'allow'}-${p.name}'),
              label: Text(permissionLabel(l, p)),
              selected: set.contains(p),
              onSelected:
                  !deny &&
                      !isAdmin &&
                      ((!set.contains(p) && !held.contains(p)) ||
                          (id == me && p == Permission.manage))
                  ? null
                  : (on) => setState(() {
                      final entry = _entries[id] ??= (
                        type,
                        <Permission>{},
                        <Permission>{},
                      );
                      final target = deny ? entry.$3 : entry.$2;
                      on ? target.add(p) : target.remove(p);
                    }),
            ),
        ],
      );
    }

    Widget row(String id, String name, PrincipalType type) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          Text(l.aclAllow, style: TextStyle(color: colors.muted, fontSize: 12)),
          chips(id, type, deny: false),
          if (type == PrincipalType.user) ...[
            Text(
              l.aclDeny,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            chips(id, type, deny: true),
          ],
        ],
      ),
    );

    return ManageFrame(
      title: l.aclTitle(folderName),
      onBack: widget.onBack,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Text(l.aclRevealNote, style: TextStyle(color: colors.muted)),
          for (final t in teams) row(t.id, t.name, PrincipalType.team),
          for (final m in members) row(m.userId, m.email, PrincipalType.user),
          if (_error case final error?)
            Text(error, style: TextStyle(color: colors.danger)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('acl-save'),
              onPressed: _busy ? null : _save,
              child: Text(l.aclSave),
            ),
          ),
        ],
      ),
    );
  }
}
