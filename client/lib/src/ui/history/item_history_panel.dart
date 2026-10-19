// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../audit/payload_diff.dart';
import '../../design/dialog.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../orgs/block_permissions.dart';
import '../../vault/org_writer.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';

/// Whether [e]'s secrets may be shown here: the server's reveal flag, and `reveal` on the folder for org items.
bool canReveal(AppState s, VaultEntry e) {
  if (!s.serverHas('reveal')) return false; // client-only flag
  final item = e.item;
  if (item.scope == ItemScope.personal) return true;
  final block = s.orgs?.block;
  if (block == null) return false;
  final folder = item.kind == ItemKind.folder ? item.id : item.folderId!;
  return explainFromBlock(
    block,
    item.orgId!,
    s.stored!.userId,
    folder,
  ).effective.contains(Permission.reveal);
}

/// One stored version, opened on this device; [meta] null = unreadable here.
typedef _Version = ({Item item, Map<String, Object?>? meta});

/// The stored versions of an item, newest first, each with its field changes; old secrets need `reveal`.
/// Restoring writes an old version back as a new revision: the history is never rewritten.
class ItemHistoryPanel extends StatefulWidget {
  const ItemHistoryPanel({super.key, required this.itemId});

  final String itemId;

  @override
  State<ItemHistoryPanel> createState() => _ItemHistoryPanelState();
}

class _ItemHistoryPanelState extends State<ItemHistoryPanel> {
  List<_Version>? _versions;

  /// revision → opened secret, once revealed.
  final _secrets = <int, Map<String, Object?>?>{};
  bool _reported = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ItemHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId == widget.itemId) return;
    _versions = null;
    _secrets.clear();
    _reported = false;
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    try {
      final items = await state.api!.revisions(widget.itemId);
      final versions = [
        for (final item in items)
          (item: item, meta: await _open(state.vault!, item, PayloadPart.meta)),
      ];
      if (mounted) setState(() => _versions = versions);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = describeError(AppLocalizations.of(context), e));
      }
    }
  }

  /// Old `_seq` values are older on purpose: opened without the replay check, no mark moves.
  static Future<Map<String, Object?>?> _open(
    Vault vault,
    Item item,
    PayloadPart part,
  ) async {
    final envelope = part == PayloadPart.meta ? item.meta : item.secret;
    if (envelope == null) return null;
    try {
      return (await vault.open(item, part, fromServer: false))?.json;
    } on Exception {
      return null;
    }
  }

  Future<void> _reveal(int index) async {
    final state = AppScope.read(context);
    final versions = _versions!;
    for (final v in [
      versions[index],
      if (index + 1 < versions.length) versions[index + 1],
    ]) {
      _secrets[v.item.revision!] = await _open(
        state.vault!,
        v.item,
        PayloadPart.secret,
      );
    }
    if (!_reported) {
      _reported = true;
      state.emit(SecretRevealed(itemId: widget.itemId));
    }
    if (mounted) setState(() {});
  }

  Future<void> _restore(_Version v) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final yes = await confirmDanger(
      context,
      question: l.historyRestoreConfirm,
      action: l.historyRestore,
    );
    if (!yes) return;
    final entry = state.vault!.entry(widget.itemId)!;
    try {
      final secret = await _open(state.vault!, v.item, PayloadPart.secret);
      if (v.item.secret != null && secret == null) {
        // writing null would drop the secret: refuse instead
        return setState(() => _error = l.historySecretUnreadable);
      }
      final orgId = entry.orgId;
      if (orgId == null) {
        await state.vault!.upsertItem(
          id: widget.itemId,
          type: entry.item.type,
          folderId: entry.folderId,
          meta: v.meta!,
          secret: secret,
        );
      } else {
        await state.orgs!.writer.upsert(
          type: entry.item.type,
          id: widget.itemId,
          target: OrgTarget(orgId, entry.folderId),
          meta: v.meta!,
          secret: secret,
        );
      }
      if (mounted) Navigator.of(context).maybePop();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  static String _show(Object? value) => switch (value) {
    null => '—',
    final List<Object?> list => list.join(', '),
    final Map<Object?, Object?> map => jsonEncode(map),
    _ => '$value',
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final entry = state.vault?.entry(widget.itemId);
    final versions = _versions;
    final restorable =
        entry != null &&
        entry.state == EntryState.ok &&
        !state.vault!.isTrashed(entry.id) &&
        !(state.sync?.readOnly ?? true);
    final reveal = entry != null && canReveal(state, entry);
    final dates = MaterialLocalizations.of(context);
    final muted = TextStyle(color: colors.muted, fontSize: 12);

    Widget changes(Map<String, Object?>? before, Map<String, Object?>? after) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in diffPayloads(before, after))
              Row(
                spacing: 8,
                children: [
                  Text(c.field, style: muted),
                  Flexible(
                    child: Text([_show(c.before), _show(c.after)].join(' → ')),
                  ),
                ],
              ),
          ],
        );

    return UfDialog(
      title: l.itemHistory,
      width: 640,
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).maybePop()),
      ],
      children: [
        if (_error case final error?)
          Text(
            error,
            key: const Key('history-error'),
            style: TextStyle(color: colors.danger),
          ),
        if (versions == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        for (final (i, v) in (versions ?? const <_Version>[]).indexed)
          Container(
            key: Key('history-rev-${v.item.revision}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  l.historyVersion(
                    v.item.revision ?? 0,
                    v.item.updatedAt == null
                        ? ''
                        : dates.formatMediumDate(v.item.updatedAt!.toLocal()),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (v.meta == null)
                  Text(l.historyUnreadable, style: muted)
                else if (i == versions!.length - 1)
                  Text(l.historyFirst, style: muted)
                else
                  changes(versions[i + 1].meta, v.meta),
                if (i + 1 < versions!.length &&
                    (v.item.secret != null ||
                        versions[i + 1].item.secret != null)) ...[
                  if (_secrets.containsKey(v.item.revision))
                    changes(
                      _secrets[versions[i + 1].item.revision],
                      _secrets[v.item.revision],
                    )
                  else if (reveal)
                    TextButton(
                      key: Key('history-reveal-${v.item.revision}'),
                      onPressed: () => _reveal(i),
                      child: Text(l.historyReveal),
                    )
                  else
                    Text(l.historySecretHidden, style: muted),
                ],
                if (i > 0)
                  TextButton(
                    key: Key('history-restore-${v.item.revision}'),
                    onPressed: restorable && v.meta != null
                        ? () => _restore(v)
                        : null,
                    child: Text(l.historyRestore),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
