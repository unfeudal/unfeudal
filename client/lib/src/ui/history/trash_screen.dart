// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/empty_state.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../vault/org_writer.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';
import 'item_history_panel.dart';

/// Items in the trash, with when the server deletes them for good; restoring puts back what was inside a folder.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  String? _error;

  Future<void> _restore(VaultEntry e) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    try {
      e.orgId == null
          ? await state.vault!.restoreItem(e.id)
          : await state.orgs!.writer.restore(e.id);
      if (mounted) setState(() => _error = null);
    } on Exception catch (err) {
      if (mounted) setState(() => _error = describeError(l, err));
    }
  }

  /// An item inside a trashed org folder moves to a live folder the user can edit (re-sealed with its keys).
  Future<void> _moveOut(VaultEntry e) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final vault = state.vault!;
    final writer = state.orgs!.writer;
    final targets = [
      for (final f in vault.ofKind(ItemKind.folder))
        if (f.orgId == e.orgId &&
            f.id != e.id &&
            f.state == EntryState.ok &&
            writer.canEdit(e.orgId!, f.id))
          f,
    ];
    final dest = await showUfDialog<String>(
      context,
      (_) => _MoveOutDialog(name: e.name ?? '', targets: targets),
    );
    if (dest == null) return;
    try {
      await writer.upsert(
        type: e.item.type,
        id: e.id,
        target: OrgTarget(e.orgId!, dest),
        meta: e.meta!,
      );
      if (mounted) setState(() => _error = null);
    } on Exception catch (err) {
      if (mounted) setState(() => _error = describeError(l, err));
    }
  }

  /// Restores and syncs change the vault: the list follows it.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).vault!,
    builder: (context, _) => _trash(context),
  );

  Widget _trash(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final readOnly = state.sync?.readOnly ?? true;
    final days = state.trashDays;
    final dates = MaterialLocalizations.of(context);
    final orgNames = {
      for (final o in state.orgs?.orgs ?? const <OrgSummary>[]) o.id: o.name,
    };
    DateTime deletedAt(VaultEntry e) => e.item.updatedAt ?? DateTime(0);
    final trashed =
        [
          for (final e in vault.entries)
            if (e.item.deleted && !e.item.purged) e,
        ]..sort((a, b) {
          // personal first ('' sorts before any org name)
          final byOrg = (orgNames[a.orgId] ?? '').compareTo(
            orgNames[b.orgId] ?? '',
          );
          return byOrg != 0 ? byOrg : deletedAt(b).compareTo(deletedAt(a));
        });
    final muted = TextStyle(color: colors.muted, fontSize: 12);
    return ManageFrame(
      title: l.trashTitle,
      onBack: widget.onBack,
      child: trashed.isEmpty
          ? EmptyState(title: l.trashTitle, body: l.trashEmpty)
          : ListView(
              children: [
                if (_error case final error?)
                  Text(error, style: TextStyle(color: colors.danger)),
                for (final e in trashed) ...[
                  ListTile(
                    key: Key('trash-${e.id}'),
                    title: Text(
                      e.state == EntryState.ok
                          ? e.name ?? ''
                          : l.treeUnreadable,
                      style: e.state == EntryState.ok
                          ? null
                          : const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.trashDeletedOn(
                            dates.formatMediumDate(deletedAt(e).toLocal()),
                          ),
                          style: muted,
                        ),
                        if (days != null)
                          Text(
                            days == 0
                                ? l.trashKept
                                : (e.orgId == null
                                      ? l.trashPurgeOn
                                      : l.trashPurgeBy)(
                                    dates.formatMediumDate(
                                      deletedAt(e)
                                          .add(Duration(days: days))
                                          .toLocal(),
                                    ),
                                  ),
                            style: muted,
                          ),
                      ],
                    ),
                    trailing: TextButton(
                      key: Key('trash-restore-${e.id}'),
                      onPressed:
                          readOnly ||
                              e.state != EntryState.ok ||
                              !canEditEntry(state, e)
                          ? null
                          : () => _restore(e),
                      child: Text(l.trashRestore),
                    ),
                  ),
                  // a trashed org folder stays readable: what is inside can be moved out before the purge
                  if (e.orgId != null && e.item.kind == ItemKind.folder)
                    for (final c in vault.entries)
                      if (c.folderId == e.id && !c.item.deleted)
                        ListTile(
                          key: Key('trash-inside-${c.id}'),
                          contentPadding: const EdgeInsets.only(
                            left: 40,
                            right: 16,
                          ),
                          dense: true,
                          title: Text(
                            c.state == EntryState.ok
                                ? c.name ?? ''
                                : l.treeUnreadable,
                          ),
                          trailing: TextButton(
                            key: Key('trash-move-out-${c.id}'),
                            onPressed:
                                readOnly ||
                                    c.state != EntryState.ok ||
                                    !canEditEntry(state, c)
                                ? null
                                : () => _moveOut(c),
                            child: Text(l.trashMoveOut),
                          ),
                        ),
                ],
              ],
            ),
    );
  }
}

class _MoveOutDialog extends StatefulWidget {
  const _MoveOutDialog({required this.name, required this.targets});

  final String name;
  final List<VaultEntry> targets;

  @override
  State<_MoveOutDialog> createState() => _MoveOutDialogState();
}

class _MoveOutDialogState extends State<_MoveOutDialog> {
  String? _dest;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return UfDialog(
      title: l.trashMoveOutTitle(widget.name),
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context)),
        FilledButton(
          key: const Key('trash-move-out-save'),
          onPressed: _dest == null ? null : () => Navigator.pop(context, _dest),
          child: Text(l.trashMoveOut),
        ),
      ],
      children: [
        if (widget.targets.isEmpty)
          Text(l.trashMoveOutNowhere)
        else
          entryPicker(
            key: 'trash-move-out-dest',
            label: l.hostFolder,
            none: l.trashMoveOutPick,
            entries: widget.targets,
            value: _dest,
            onChanged: (v) => setState(() => _dest = v),
          ),
      ],
    );
  }
}
