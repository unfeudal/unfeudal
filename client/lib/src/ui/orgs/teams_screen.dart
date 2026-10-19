// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../manage_frame.dart';

/// The org's teams (with the `teams` capability): create, rename, change members, delete.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.orgId, this.onBack});

  final String orgId;
  final VoidCallback? onBack;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  /// The team being edited: null id for a new one; null while none is open.
  ({String? id, TextEditingController name, Set<String> memberIds})? _editing;
  String? _error;

  @override
  void dispose() {
    _editing?.name.dispose();
    super.dispose();
  }

  void _edit(OrgTeam? team) => setState(() {
    _editing?.name.dispose();
    _editing = (
      id: team?.id,
      name: TextEditingController(text: team?.name ?? ''),
      memberIds: {...?team?.memberIds},
    );
  });

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final editing = _editing!;
    final name = editing.name.text.trim();
    if (name.isEmpty) return setState(() => _error = l.fieldRequired);
    try {
      final memberIds = editing.memberIds.toList()..sort();
      editing.id == null
          ? await state.api!.createTeam(
              widget.orgId,
              name: name,
              memberIds: memberIds,
            )
          : await state.api!.updateTeam(
              widget.orgId,
              editing.id!,
              name: name,
              memberIds: memberIds,
            );
      await state.sync!.syncNow();
      if (mounted) {
        setState(() {
          _editing?.name.dispose();
          _editing = null;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  Future<void> _delete(OrgTeam team) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final yes = await confirmDanger(
      context,
      question: l.teamDeleteConfirm(team.name),
      action: l.teamDelete,
    );
    if (!yes) return;
    try {
      await state.api!.deleteTeam(widget.orgId, team.id);
      await state.sync!.syncNow();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final block = state.orgs!.block;
    final enabled = state.serverHas('teams');
    final teams = [
      for (final t in block?.teams ?? const <OrgTeam>[])
        if (t.orgId == widget.orgId) t,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final members = [
      for (final m in block?.members ?? const <OrgMember>[])
        if (m.orgId == widget.orgId) m,
    ]..sort((a, b) => a.email.compareTo(b.email));
    final editing = _editing;
    return ManageFrame(
      title: l.teamsTitle,
      onBack: widget.onBack,
      child: !enabled
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const Key('team-new'),
                    onPressed: () => _edit(null),
                    child: Text(l.teamNew),
                  ),
                ),
                if (editing != null) ...[
                  TextField(
                    key: const Key('team-name'),
                    controller: editing.name,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: l.teamName),
                  ),
                  for (final m in members)
                    CheckboxListTile(
                      key: Key('team-member-${m.userId}'),
                      value: editing.memberIds.contains(m.userId),
                      title: Text(m.email),
                      onChanged: (on) => setState(
                        () => on == true
                            ? editing.memberIds.add(m.userId)
                            : editing.memberIds.remove(m.userId),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('team-save'),
                      onPressed: _save,
                      child: Text(l.teamSave),
                    ),
                  ),
                ],
                if (_error case final error?)
                  Text(error, style: TextStyle(color: colors.danger)),
                for (final t in teams)
                  ListTile(
                    key: Key('team-${t.id}'),
                    title: Text(t.name),
                    subtitle: Text(
                      [
                        for (final m in members)
                          if (t.memberIds.contains(m.userId)) m.email,
                      ].join(', '),
                    ),
                    onTap: () => _edit(t),
                    trailing: IconButton(
                      key: Key('team-delete-${t.id}'),
                      tooltip: l.teamDelete,
                      onPressed: () => _delete(t),
                      icon: const Icon(UfIcons.trash, size: 16),
                    ),
                  ),
              ],
            ),
    );
  }
}
