// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/field.dart';
import '../../vault/vault.dart';

/// Picks the jump host of a host ([hostId]) or the default of a folder ([folderId], [hostId] null). Only
/// candidates that leave every affected chain free of loops, missing hops and excess depth are offered.
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
    final candidates = [
      for (final e in vault.ofKind(ItemKind.host))
        if (e.state == EntryState.ok &&
            e.id != hostId &&
            (e.id == value || _isClean(vault, e.id)))
          e,
    ];
    final inherits = value == null && inheritedId != null;
    return UfField(
      label: l.hostJump,
      source: inherits && inheritedFrom != null
          ? l.hostInherited(inheritedFrom!)
          : null,
      child: DropdownButtonFormField<String?>(
        initialValue: candidates.any((e) => e.id == value) ? value : null,
        // the null entry inherits: it shows the inherited host when there is one
        selectedItemBuilder: (context) => [
          Text(inherits ? vault.entry(inheritedId!)?.name ?? '' : l.jumpNone),
          for (final e in candidates) Text(e.name ?? ''),
        ],
        items: [
          DropdownMenuItem(
            key: const Key('jump-option-none'),
            child: Text(l.jumpNone),
          ),
          for (final e in candidates)
            DropdownMenuItem(
              key: Key('jump-option-${e.id}'),
              value: e.id,
              child: Text(e.name ?? ''),
            ),
        ],
        onChanged: onChanged,
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
