// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../audit/payload_diff.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../vault/vault.dart';
import '../busy_action.dart';

// One stored version, opened on this device; a null meta means unreadable here.
typedef _Version = ({Item item, Map<String, Object?>? meta});

/// The stored versions of an item, newest first, each with its field changes; old secrets need `reveal`.
/// Restoring writes an old version back as a new revision: the history is never rewritten.
class ItemHistoryPanel extends StatefulWidget {
  /// In its own dialog.
  const ItemHistoryPanel({super.key, required this.itemId}) : embedded = false;

  /// The version list alone, for the inspector's Historique tab.
  const ItemHistoryPanel.embedded({super.key, required this.itemId})
    : embedded = true;

  final String itemId;
  final bool embedded;

  @override
  State<ItemHistoryPanel> createState() => _ItemHistoryPanelState();
}

class _ItemHistoryPanelState extends State<ItemHistoryPanel> with BusyAction {
  List<_Version>? _versions;

  // Opened secret by revision, once revealed.
  final _secrets = <int, Map<String, Object?>?>{};
  bool _reported = false;

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

  Future<void> _load() => run(() async {
    final state = AppScope.read(context);
    final items = await state.api!.revisions(widget.itemId);
    final versions = [
      for (final item in items)
        (item: item, meta: await _open(state.vault!, item, PayloadPart.meta)),
    ];
    if (mounted) setState(() => _versions = versions);
  });

  // Old `_seq` values are older on purpose: opened without the replay check, no mark moves.
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
    await run(() async {
      final secret = await _open(state.vault!, v.item, PayloadPart.secret);
      if (v.item.secret != null && secret == null) {
        // writing null would drop the secret: refuse instead
        return setState(() => problem = l.historySecretUnreadable);
      }
      await state.saveItem(
        type: entry.item.type,
        id: widget.itemId,
        orgId: entry.orgId,
        folderId: entry.folderId,
        meta: v.meta!,
        secret: secret,
      );
      if (!mounted) return;
      if (widget.embedded) {
        setState(() => _versions = null);
        await _load();
      } else {
        await Navigator.of(context).maybePop();
      }
    });
  }

  static String _show(Object? value) => switch (value) {
    null => noValue,
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
        state.orgs!.canEditEntry(entry) &&
        !state.vault!.isTrashed(entry.id) &&
        !(state.sync?.readOnly ?? true);
    final reveal =
        entry != null &&
        state.serverHas(Flag.reveal) && // client-only flag
        state.orgs!.canReveal(entry);
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

    final children = [
      if (problem case final error?)
        UfErrorLine(error, key: const Key('history-error')),
      if (versions == null && problem == null)
        Center(child: UfLoading(l.loading)),
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
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return UfDialog(
      title: l.itemHistory,
      width: 640,
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).maybePop()),
      ],
      children: children,
    );
  }
}
