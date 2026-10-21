// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/choices.dart';
import '../../design/field.dart';
import '../../design/inputs.dart';
import '../../vault/vault.dart';

/// Picks the jump host of a host ([hostId]) or the default of a folder ([folderId], [hostId] null). Only
/// candidates that leave every affected chain free of loops, missing hops and excess depth can be picked.
class JumpHostPicker extends StatelessWidget {
  const JumpHostPicker({
    required Key key,
    required this.hostId,
    this.folderId,
    required this.value,
    this.inheritedId,
    this.inheritedFrom,
    required this.onChanged,
  }) : super(key: key);

  final String? hostId;
  final String? folderId;

  /// Null inherits.
  final String? value;
  final String? inheritedId;

  /// The folder name [inheritedId] comes from.
  final String? inheritedFrom;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final vault = AppScope.of(context).vault!;
    final hosts = [
      for (final e in vault.ofKind(ItemKind.host))
        if (e.state == EntryState.ok && e.id != hostId)
          (
            entry: e,
            refused:
                e.id == value ||
                    vault.jumpKeepsChainsValid(
                      hostId: hostId,
                      folderId: folderId,
                      candidate: e.id,
                    )
                ? null
                : l.jumpBreaksChain,
          ),
    ];
    final inherits = value == null && inheritedId != null;
    final inherited = inherits ? vault.entry(inheritedId!)?.name ?? '' : null;
    final change = onChanged;
    return UfField(
      label: l.hostJump,
      source: inherits && inheritedFrom != null
          ? l.hostInherited(inheritedFrom!)
          : null,
      // a long list is filtered by typing; the null option inherits, showing the inherited host
      child: hosts.length > 8 && change != null
          ? UfCombobox<String?>(
              value: value,
              options: [
                UfComboOption(null, l.jumpNone, detail: inherited),
                for (final (:entry, :refused) in hosts)
                  UfComboOption(
                    entry.id,
                    entry.name ?? '',
                    disabledReason: refused,
                  ),
              ],
              onSelected: change,
            )
          : UfSelect<String?>(
              value: hosts.any((h) => h.entry.id == value) ? value : null,
              selectedLabel: inherited,
              options: [
                UfOption(null, l.jumpNone, key: const Key('jump-option-none')),
                for (final (:entry, :refused) in hosts)
                  UfOption(
                    entry.id,
                    entry.name ?? '',
                    key: Key('jump-option-${entry.id}'),
                    enabled: refused == null,
                  ),
              ],
              onChanged: change,
            ),
    );
  }
}
