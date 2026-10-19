// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/empty_state.dart';
import '../../design/tokens.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import '../manage_frame.dart';

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
                for (final e in trashed)
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
                      onPressed: readOnly || e.state != EntryState.ok
                          ? null
                          : () => _restore(e),
                      child: Text(l.trashRestore),
                    ),
                  ),
              ],
            ),
    );
  }
}
