// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import 'editor_frame.dart';
import 'host_editor_panel.dart';

/// Edits a folder: name, parent (never itself or inside itself) and defaults for the hosts inside.
class FolderEditorPanel extends StatefulWidget {
  const FolderEditorPanel({
    super.key,
    this.folderId,
    this.parentId,
    this.onClose,
  });

  /// Null for a new folder.
  final String? folderId;

  /// Parent of a new folder.
  final String? parentId;
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
  final _problems = <String, String>{};
  String? _error;
  int _failures = 0;

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
    _parentId = entry?.folderId ?? widget.parentId;
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
    final vault = AppScope.read(context).vault!;
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
    if (meta == null) return setState(() => _failures++);
    try {
      await vault.saveFolder(meta, id: widget.folderId, parentId: _parentId);
      widget.onClose?.call();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final vault = AppScope.read(context).vault!;
    final yes = await showUfDialog<bool>(
      context,
      (dialog) => AlertDialog(
        content: Text(l.folderDeleteConfirm(_name.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(MaterialLocalizations.of(dialog).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('confirm-yes'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(l.folderDelete),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await vault.deleteFolder(widget.folderId!);
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
        if (e.state == EntryState.ok && !excluded.contains(e.id)) e,
    ];
    final identities = vault
        .ofKind(ItemKind.identity)
        .where((e) => e.state == EntryState.ok)
        .toList();
    InputDecoration decoration(String label, String field) =>
        InputDecoration(labelText: label, errorText: _problems[field]);
    return EditorFrame(
      width: HostEditorPanel.width,
      onClose: widget.onClose,
      children: [
        ShakeOnError(
          trigger: _failures,
          child: TextField(
            key: const Key('folder-name'),
            controller: _name,
            decoration: decoration(l.folderName, 'name'),
          ),
        ),
        DropdownButtonFormField<String?>(
          key: const Key('folder-parent'),
          initialValue: parents.any((e) => e.id == _parentId)
              ? _parentId
              : null,
          decoration: InputDecoration(labelText: l.folderParent),
          items: [
            DropdownMenuItem(
              key: const Key('folder-parent-root'),
              child: Text(l.folderRoot),
            ),
            for (final e in parents)
              DropdownMenuItem(
                key: Key('folder-parent-${e.id}'),
                value: e.id,
                child: Text(e.name ?? ''),
              ),
          ],
          onChanged: (v) => setState(() => _parentId = v),
        ),
        Text(l.folderDefaults, style: Theme.of(context).textTheme.titleSmall),
        TextField(
          key: const Key('folder-port'),
          controller: _port,
          decoration: decoration(l.hostPort, 'port'),
        ),
        TextField(
          key: const Key('folder-user'),
          controller: _user,
          decoration: decoration(l.hostUser, 'user'),
        ),
        DropdownButtonFormField<String?>(
          key: const Key('folder-identity'),
          initialValue: identities.any((e) => e.id == _identityId)
              ? _identityId
              : null,
          decoration: InputDecoration(labelText: l.hostIdentity),
          items: [
            DropdownMenuItem(child: Text(l.hostDefault)),
            for (final e in identities)
              DropdownMenuItem(value: e.id, child: Text(e.name ?? '')),
          ],
          onChanged: (v) => setState(() => _identityId = v),
        ),
        if (_error case final error?)
          Text(error, style: TextStyle(color: UfColors.of(context).danger)),
        FilledButton(
          key: const Key('folder-save'),
          onPressed: readOnly ? null : _save,
          child: Text(l.folderSave),
        ),
        if (widget.folderId != null && !readOnly)
          TextButton(
            key: const Key('folder-delete'),
            onPressed: _delete,
            child: Text(l.folderDelete),
          ),
      ],
    );
  }
}
