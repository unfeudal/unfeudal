// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/empty_state.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../vault/org_writer.dart';
import '../../vault/vault.dart';
import '../busy_action.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';

/// The selected vault's trash, with when the server deletes each item for good; restoring puts back what was
/// inside a folder.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> with BusyAction {
  Future<void> _restore(VaultEntry e) async {
    final state = AppScope.read(context);
    await run(() => state.restoreItem(e.id));
  }

  // An item inside a trashed org folder moves to a live folder the user can edit (re-sealed with its keys).
  Future<void> _moveOut(VaultEntry e) async {
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
    await run(
      () => writer.upsert(
        type: e.item.type,
        id: e.id,
        target: OrgTarget(e.orgId!, dest),
        meta: e.meta!,
      ),
    );
  }

  /// Restores and syncs change the vault: the list follows it.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).vault!,
    builder: (context, _) => _trash(context),
  );

  Widget _trash(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final readOnly = state.sync?.readOnly ?? true;
    final days = state.trashDays;
    final dates = MaterialLocalizations.of(context);
    final orgId = state.orgs?.selected;
    final vaultName = vaultNameOf(l, state, orgId);
    DateTime deletedAt(VaultEntry e) => e.item.updatedAt ?? DateTime(0);
    final trashed = [
      for (final e in vault.entries)
        if (e.item.deleted && !e.item.purged && e.orgId == orgId) e,
    ]..sort((a, b) => deletedAt(b).compareTo(deletedAt(a)));
    String when(VaultEntry e) => [
      l.trashDeletedOn(dates.formatMediumDate(deletedAt(e).toLocal())),
      if (days != null)
        days == 0
            ? l.trashKept
            : (e.orgId == null ? l.trashPurgeOn : l.trashPurgeBy)(
                dates.formatMediumDate(
                  deletedAt(e).add(Duration(days: days)).toLocal(),
                ),
              ),
    ].join(' · ');
    bool blocked(VaultEntry e) =>
        readOnly || e.state != EntryState.ok || !state.orgs!.canEditEntry(e);
    return ManageFrame(
      title: l.trashTitle,
      subtitle: vaultName,
      onBack: widget.onBack,
      maxWidth: trashed.isEmpty ? null : 980,
      child: trashed.isEmpty
          ? EmptyState(title: l.trashTitle, body: l.trashEmpty)
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (problem case final error?) UfErrorLine(error),
                for (final e in trashed) ...[
                  ItemRow(
                    key: Key('trash-${e.id}'),
                    icon: _icon(e.item.kind),
                    title: e.state == EntryState.ok
                        ? e.name ?? ''
                        : l.treeUnreadable,
                    dimmed: e.state != EntryState.ok,
                    subtitle: when(e),
                    trailing: [
                      OutlinedButton(
                        key: Key('trash-restore-${e.id}'),
                        style: smallButton,
                        onPressed: blocked(e) ? null : () => _restore(e),
                        child: Text(l.trashRestore),
                      ),
                    ],
                  ),
                  // a trashed org folder stays readable: what is inside can be moved out before the purge
                  if (e.orgId != null && e.item.kind == ItemKind.folder)
                    for (final c in vault.entries)
                      if (c.folderId == e.id && !c.item.deleted)
                        Padding(
                          padding: const EdgeInsets.only(left: 44),
                          child: ItemRow(
                            key: Key('trash-inside-${c.id}'),
                            icon: _icon(c.item.kind),
                            title: c.state == EntryState.ok
                                ? c.name ?? ''
                                : l.treeUnreadable,
                            dimmed: c.state != EntryState.ok,
                            trailing: [
                              OutlinedButton(
                                key: Key('trash-move-out-${c.id}'),
                                style: smallButton,
                                onPressed: blocked(c)
                                    ? null
                                    : () => _moveOut(c),
                                child: Text(l.trashMoveOut),
                              ),
                            ],
                          ),
                        ),
                ],
              ],
            ),
    );
  }

  static IconData _icon(ItemKind? kind) => switch (kind) {
    ItemKind.folder => UfIcons.folderSimple,
    ItemKind.identity => UfIcons.key,
    ItemKind.snippet => UfIcons.terminal,
    _ => UfIcons.desktop,
  };
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
