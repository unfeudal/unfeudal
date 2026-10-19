// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/field.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import 'editor_frame.dart';

/// Edits a host; empty port, user and key show the inherited value and where it comes from.
class HostEditorPanel extends StatefulWidget {
  const HostEditorPanel({super.key, this.hostId, this.folderId, this.onClose});

  /// Null for a new host.
  final String? hostId;

  /// Folder of a new host.
  final String? folderId;
  final VoidCallback? onClose;

  @override
  State<HostEditorPanel> createState() => _HostEditorPanelState();
}

class _HostEditorPanelState extends State<HostEditorPanel> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  final _startup = TextEditingController();
  String? _identityId;
  String? _folderId;
  final _problems = <String, String>{};
  String? _error;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    final meta = _entry?.meta ?? const {};
    String text(String key) => switch (meta[key]) {
      final Object v => '$v',
      null => '',
    };
    _name.text = text('name');
    _address.text = text('address');
    _port.text = text('port');
    _user.text = text('user');
    _tags.text = switch (meta['tags']) {
      final List<Object?> tags => tags.join(', '),
      _ => '',
    };
    _notes.text = text('notes');
    _startup.text = text('startupCommand');
    _identityId = meta['identityId'] as String?;
    _folderId = _entry?.folderId ?? widget.folderId;
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _port, _user, _tags, _notes, _startup]) {
      c.dispose();
    }
    super.dispose();
  }

  VaultEntry? get _entry => widget.hostId == null
      ? null
      : AppScope.read(context).vault!.entry(widget.hostId!);

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final vault = state.vault!;
    _problems.clear();
    if (_name.text.trim().isEmpty) _problems['name'] = l.fieldRequired;
    if (_address.text.trim().isEmpty) _problems['address'] = l.fieldRequired;
    final port = _port.text.trim().isEmpty
        ? null
        : int.tryParse(_port.text.trim());
    if (_port.text.trim().isNotEmpty &&
        (port == null || port < 1 || port > 65535)) {
      _problems['port'] = l.fieldInvalid;
    }
    String? optional(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final meta = {
      'schemaVersion': 1,
      ...?_entry?.meta, // fields this editor does not show (forwards, jump host, unknown keys) are kept
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'port': port,
      'user': optional(_user),
      'identityId': _identityId,
      'tags': [
        for (final t in _tags.text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ],
      'notes': optional(_notes),
      'startupCommand': optional(_startup),
    };
    if (_problems.isEmpty) {
      try {
        HostMeta.fromJson(meta);
      } on FormatException catch (e) {
        _problems[_fieldOf(e)] = l.fieldInvalid;
      }
    }
    if (_problems.isNotEmpty) return setState(() => _failures++);
    try {
      final isNew = widget.hostId == null;
      final id = await vault.upsertItem(
        type: 'host',
        id: widget.hostId,
        folderId: _folderId,
        meta: meta,
      );
      if (isNew) {
        state.emit(
          HostCreated(
            hostId: id,
            name: _name.text.trim(),
            total: vault.ofKind(ItemKind.host).length,
          ),
        );
      }
      widget.onClose?.call();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  /// `host.<field>: …` → the field to mark; anything else marks the name.
  static String _fieldOf(FormatException e) =>
      RegExp(r'^host\.(\w+)').firstMatch(e.message)?.group(1) ?? 'name';

  Future<void> _trash() async {
    await AppScope.read(context).vault!.trashItem(widget.hostId!);
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final entry = _entry;
    final notice = switch (entry) {
      VaultEntry(state: EntryState.readOnly) => l.itemNewer,
      VaultEntry(:final id) when vault.isTrashed(id) => l.itemTrashed,
      _ => null,
    };
    final editable = notice == null;
    final resolved = entry == null || entry.state != EntryState.ok
        ? null
        : vault.hostLookup(entry.id)?.resolved;
    String? source(String field) => switch (resolved?.sources[field]) {
      null => null,
      'default' => l.hostDefault,
      final String folder => l.hostInherited(vault.entry(folder)?.name ?? ''),
    };

    /// An empty inheritable field shows the resolved value as a hint and its source under it.
    Widget field(
      String key,
      TextEditingController controller,
      String label,
      String problemKey, {
      Object? resolvedValue,
      bool inheritable = false,
      int lines = 1,
      bool mono = false,
    }) {
      final inherits = inheritable && controller.text.trim().isEmpty;
      return UfField(
        label: label,
        source: inherits ? source(problemKey) : null,
        error: _problems[problemKey],
        child: TextField(
          key: Key(key),
          controller: controller,
          readOnly: !editable,
          maxLines: lines,
          onChanged: inheritable ? (_) => setState(() {}) : null,
          style: mono ? monoStyle.copyWith(fontSize: 13) : null,
          decoration: InputDecoration(
            hintText: inherits && resolvedValue != null
                ? '$resolvedValue'
                : null,
          ),
        ),
      );
    }

    final identities = vault
        .ofKind(ItemKind.identity)
        .where((e) => e.state == EntryState.ok)
        .toList();
    final folders = vault
        .ofKind(ItemKind.folder)
        .where((e) => e.state == EntryState.ok)
        .toList();
    final folderName = vault.entry(_folderId ?? '')?.name;
    final readOnly = state.sync?.readOnly ?? true;
    return EditorFrame(
      title: entry?.name ?? l.treeNewHost,
      crumb: [l.vaultPersonal, ?folderName].join(' / '),
      notice: notice,
      onClose: widget.onClose,
      save: editable
          ? FilledButton(
              key: const Key('host-save'),
              onPressed: readOnly ? null : _save,
              child: Text(l.hostSave),
            )
          : null,
      trash: editable && entry != null && !readOnly
          ? TextButton(
              key: const Key('host-delete'),
              onPressed: _trash,
              child: Text(l.hostDelete),
            )
          : null,
      children: [
        ShakeOnError(
          trigger: _failures,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              field('host-name', _name, l.hostName, 'name'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Expanded(
                    flex: 2,
                    child: field(
                      'host-address',
                      _address,
                      l.hostAddress,
                      'address',
                    ),
                  ),
                  Expanded(
                    child: field(
                      'host-port',
                      _port,
                      l.hostPort,
                      'port',
                      inheritable: true,
                      resolvedValue: resolved?.port,
                    ),
                  ),
                ],
              ),
              field(
                'host-user',
                _user,
                l.hostUser,
                'user',
                inheritable: true,
                resolvedValue: resolved?.user,
              ),
            ],
          ),
        ),
        entryPicker(
          key: 'host-identity',
          label: l.hostIdentity,
          none: l.hostDefault,
          entries: identities,
          value: _identityId,
          source: _identityId == null ? source('identityId') : null,
          onChanged: editable ? (v) => setState(() => _identityId = v) : null,
        ),
        entryPicker(
          key: 'host-folder',
          label: l.hostFolder,
          none: l.folderRoot,
          entries: folders,
          value: _folderId,
          onChanged: editable ? (v) => setState(() => _folderId = v) : null,
        ),
        field('host-tags', _tags, l.hostTags, 'tags'),
        field('host-notes', _notes, l.hostNotes, 'notes', lines: 3),
        field(
          'host-startup',
          _startup,
          l.hostStartup,
          'startupCommand',
          mono: true,
        ),
        if (_error case final error?)
          Text(error, style: TextStyle(color: UfColors.of(context).danger)),
      ],
    );
  }
}
