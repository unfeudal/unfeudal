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
            refused: e.id == value || _isClean(vault, e.id)
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

  bool _isClean(Vault vault, String candidate) {
    try {
      if (hostId case final host?) {
        resolveJumpChain(
          host,
          (id) => id == host
              ? _withJump(vault, host, candidate)
              : _lookup(vault, id),
        );
        return true;
      }
      final folder = folderId;
      if (folder == null) {
        return true; // a new folder: no host inherits from it yet
      }
      final draft = _draftFolder(vault, folder, candidate);
      ResolvedHost? lookup(String id) {
        final e = vault.entry(id);
        if (e == null || vault.isTrashed(id) || vault.hostLookup(id) == null) {
          return null;
        }
        return resolveHost(
          HostMeta.fromJson(e.meta),
          e.folderId,
          (f) => f == folder ? draft : _folderMeta(vault, f),
          hostId: id,
          parentOf: (f) => vault.entry(f)?.folderId,
        );
      }

      for (final e in vault.ofKind(ItemKind.host)) {
        if (lookup(e.id)?.sources['jumpHostId'] == folder) {
          resolveJumpChain(e.id, lookup);
        }
      }
      return true;
    } on Exception {
      return false; // JumpLoop, JumpTooDeep or JumpHostMissing
    }
  }

  static ResolvedHost? _lookup(Vault vault, String id) =>
      vault.isTrashed(id) ? null : vault.hostLookup(id)?.resolved;

  static ResolvedHost? _withJump(Vault vault, String id, String jump) {
    final r = _lookup(vault, id);
    return r == null
        ? null
        : ResolvedHost(
            port: r.port,
            user: r.user,
            identityId: r.identityId,
            jumpHostId: jump,
            sources: {...r.sources, 'jumpHostId': 'host'},
          );
  }

  static FolderMeta? _folderMeta(Vault vault, String id) {
    final e = vault.entry(id);
    return e != null && e.state == EntryState.ok && e.kind == ItemKind.folder
        ? FolderMeta.fromJson(e.meta)
        : null;
  }

  static FolderMeta? _draftFolder(Vault vault, String id, String jump) {
    final e = vault.entry(id);
    if (e == null || e.state != EntryState.ok) return null;
    final defaults = switch (e.meta?['defaults']) {
      final Map<String, Object?> d => d,
      _ => const <String, Object?>{},
    };
    return FolderMeta.fromJson({
      ...?e.meta,
      'defaults': {...defaults, 'jumpHostId': jump},
    });
  }
}
