// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';

/// The org's teams (with the `teams` capability): create, rename, change members, delete.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.orgId});

  final String orgId;

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
    final members = state.orgs!.membersOf(widget.orgId);
    final editing = _editing;
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    if (!enabled) return const SizedBox.shrink();
    // a Material of its own: the section, a dialog or a test may host it
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('team-new'),
              icon: const Icon(UfIcons.plus),
              onPressed: () => _edit(null),
              label: Text(l.teamNew),
            ),
          ),
          if (editing != null)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    UfField(
                      label: l.teamName,
                      child: TextField(
                        key: const Key('team-name'),
                        controller: editing.name,
                        maxLength: 100,
                      ),
                    ),
                    for (final m in members)
                      CheckboxListTile(
                        key: Key('team-member-${m.userId}'),
                        value: editing.memberIds.contains(m.userId),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
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
                ),
              ),
            ),
          if (_error case final error?)
            Text(error, style: TextStyle(color: colors.danger)),
          const SizedBox(height: 8),
          if (teams.isEmpty && editing == null)
            Text(l.teamsEmpty, style: muted),
          for (final t in teams)
            InkWell(
              key: Key('team-${t.id}'),
              onTap: () => _edit(t),
              child: ItemRow(
                icon: UfIcons.usersThree,
                title: t.name,
                subtitle: [
                  for (final m in members)
                    if (t.memberIds.contains(m.userId)) m.email,
                ].join(', '),
                trailing: [
                  IconButton(
                    key: Key('team-delete-${t.id}'),
                    tooltip: l.teamDelete,
                    onPressed: () => _delete(t),
                    icon: const Icon(UfIcons.trash),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
