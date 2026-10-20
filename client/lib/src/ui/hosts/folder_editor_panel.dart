// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/feedback.dart';
import '../../design/field.dart';
import '../../vault/org_writer.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import '../history/item_history_panel.dart';
import '../fields.dart';
import 'access_tab.dart';
import 'editor_frame.dart';
import 'jump_host_picker.dart';

/// Edits a folder: name, parent (never itself or inside itself) and defaults for the hosts inside.
class FolderEditorPanel extends StatefulWidget {
  const FolderEditorPanel({super.key, this.folderId, this.orgId, this.onClose});

  /// Null for a new folder.
  final String? folderId;

  /// Org of a new folder; null for the personal vault.
  final String? orgId;
  final VoidCallback? onClose;

  @override
  State<FolderEditorPanel> createState() => _FolderEditorPanelState();
}

class _FolderEditorPanelState extends State<FolderEditorPanel> {
  final _name = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  String? _parentId;
  String? _identityId;
  String? _jumpHostId;
  final _problems = <String, String>{};
  String? _error;

  /// Bumped by a refused save, to shake the panel.
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    final entry = _entry;
    final meta = entry?.meta ?? const {};
    final defaults = switch (meta['defaults']) {
      final Map<String, Object?> d => d,
      _ => const <String, Object?>{},
    };
    _name.text = (meta['name'] as String?) ?? '';
    _port.text = defaults['port'] == null ? '' : '${defaults['port']}';
    _user.text = (defaults['user'] as String?) ?? '';
    _identityId = defaults['identityId'] as String?;
    _jumpHostId = defaults['jumpHostId'] as String?;
    _parentId = entry?.folderId;
  }

  @override
  void dispose() {
    for (final c in [_name, _port, _user]) {
      c.dispose();
    }
    super.dispose();
  }

  VaultEntry? get _entry => widget.folderId == null
      ? null
      : AppScope.read(context).vault!.entry(widget.folderId!);

  String? get _orgId => _entry?.orgId ?? widget.orgId;

  /// The folder itself and every folder below it: never a valid parent.
  Set<String> _subtree(Vault vault) {
    final id = widget.folderId;
    if (id == null) return const {};
    final out = {id};
    for (var grew = true; grew;) {
      grew = false;
      for (final e in vault.ofKind(ItemKind.folder)) {
        if (out.contains(e.folderId) && out.add(e.id)) grew = true;
      }
    }
    return out;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final vault = state.vault!;
    _problems.clear();
    if (_name.text.trim().isEmpty) _problems['name'] = l.fieldRequired;
    final port = _port.text.trim().isEmpty
        ? null
        : int.tryParse(_port.text.trim());
    if (_port.text.trim().isNotEmpty &&
        (port == null || port < 1 || port > 65535)) {
      _problems['port'] = l.fieldInvalid;
    }
    final previous = _entry?.meta ?? const {};
    final previousDefaults = switch (previous['defaults']) {
      final Map<String, Object?> d => d,
      _ => const <String, Object?>{},
    };
    final json = {
      'schemaVersion': 1,
      ...previous, // unknown keys kept
      'name': _name.text.trim(),
      'defaults': {
        ...previousDefaults,
        'port': port,
        'user': _user.text.trim().isEmpty ? null : _user.text.trim(),
        'identityId': _identityId,
        'jumpHostId': _jumpHostId,
      },
    };
    FolderMeta? meta;
    if (_problems.isEmpty) {
      try {
        meta = FolderMeta.fromJson(json);
      } on FormatException {
        _problems['name'] = l.fieldInvalid;
      }
    }
    if (meta == null) return setState(() => _shakes++);
    try {
      final orgId = _orgId;
      if (orgId == null) {
        await vault.saveFolder(meta, id: widget.folderId, parentId: _parentId);
      } else if (widget.folderId == null) {
        await state.orgs!.writer.createFolder(
          orgId: orgId,
          parentId: _parentId,
          meta: meta,
        );
      } else {
        await state.orgs!.writer.upsert(
          type: 'folder',
          id: widget.folderId,
          target: OrgTarget(orgId, _parentId),
          meta: meta.toJson(),
        );
      }
      widget.onClose?.call();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final yes = await confirmDanger(
      context,
      question: l.folderDeleteConfirm(_name.text),
      action: l.folderDelete,
    );
    if (!yes) return;
    await state.trashItem(widget.folderId!, orgId: _orgId);
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final readOnly = state.sync?.readOnly ?? true;
    final excluded = _subtree(vault);
    final parents = [
      for (final e in vault.ofKind(ItemKind.folder))
        if (e.state == EntryState.ok &&
            e.orgId == _orgId &&
            !excluded.contains(e.id))
          e,
    ];
    final identities = vault
        .ofKind(ItemKind.identity)
        .where((e) => e.state == EntryState.ok && e.orgId == _orgId)
        .toList();
    final parentName = vault.entry(_parentId ?? '')?.name;
    return UfShake(
      shakes: _shakes,
      child: EditorFrame(
        title: widget.folderId == null
            ? l.treeNewFolder
            : vault.entry(widget.folderId!)?.name ?? l.treeNewFolder,
        crumb: [vaultNameOf(l, state, _orgId), ?parentName].join(' / '),
        tabs: [
          if ((_orgId, widget.folderId) case (final org?, final folder?))
            (l.inspectorTabAccess, [AccessTab(orgId: org, folderId: folder)]),
          if (state.serverHas('item_history') && widget.folderId != null)
            (
              l.itemHistory,
              [ItemHistoryPanel.embedded(itemId: widget.folderId!)],
            ),
        ],
        onClose: widget.onClose,
        save: FilledButton(
          key: const Key('folder-save'),
          onPressed: readOnly ? null : _save,
          child: Text(l.folderSave),
        ),
        trash: widget.folderId != null && !readOnly
            ? TextButton(
                key: const Key('folder-delete'),
                onPressed: _delete,
                child: Text(l.folderDelete),
              )
            : null,
        children: [
          keyedField(
            'folder-name',
            _name,
            l.folderName,
            error: _problems['name'],
          ),
          entryPicker(
            key: 'folder-parent',
            label: l.folderParent,
            none: l.folderRoot,
            entries: parents,
            value: _parentId,
            onChanged: (v) => setState(() => _parentId = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.folderDefaults,
              style: Theme.of(context).textTheme.titleMedium!
                  .copyWith(fontSize: 14),
            ),
          ),
          keyedField(
            'folder-port',
            _port,
            l.hostPort,
            error: _problems['port'],
          ),
          keyedField(
            'folder-user',
            _user,
            l.hostUser,
            error: _problems['user'],
          ),
          entryPicker(
            key: 'folder-identity',
            label: l.hostIdentity,
            none: l.hostDefault,
            entries: identities,
            value: _identityId,
            onChanged: (v) => setState(() => _identityId = v),
          ),
          JumpHostPicker(
            key: const Key('folder-jump'),
            hostId: null,
            folderId: widget.folderId,
            value: _jumpHostId,
            onChanged: (v) => setState(() => _jumpHostId = v),
          ),
          if (_error case final error?) UfErrorLine(error),
        ],
      ),
    );
  }
}
