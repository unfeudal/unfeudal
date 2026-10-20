// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/choices.dart';
import '../../design/feedback.dart';
import '../../design/field.dart';
import '../../design/inputs.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../vault/vault.dart';
import '../busy_action.dart';
import '../history/item_history_panel.dart';
import 'access_tab.dart';
import 'editor_frame.dart';
import 'forwards_editor.dart';
import 'host_binding_field.dart';
import 'jump_host_picker.dart';

/// Edits a host; empty port, user and key show the inherited value and where it comes from.
class HostEditorPanel extends StatefulWidget {
  const HostEditorPanel({super.key, this.hostId, this.orgId, this.onClose});

  /// Null for a new host.
  final String? hostId;

  /// Org of a new host; null for the personal vault.
  final String? orgId;
  final VoidCallback? onClose;

  @override
  State<HostEditorPanel> createState() => _HostEditorPanelState();
}

class _HostEditorPanelState extends State<HostEditorPanel> with BusyAction {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _user = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  final _startup = TextEditingController();
  int? _port;
  String? _identityId;
  String? _folderId;
  String? _jumpHostId;
  IdentityMode _identityMode = IdentityMode.shared;

  // Null while a forward row has a problem.
  List<PortForward>? _forwards = const [];
  final _problems = <String, String>{};

  // Bumped by a refused save, to shake the panel.
  int _shakes = 0;

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
    _port = switch (meta['port']) {
      final int port => port,
      _ => null,
    };
    _user.text = text('user');
    _tags.text = switch (meta['tags']) {
      final List<Object?> tags => tags.join(', '),
      _ => '',
    };
    _notes.text = text('notes');
    _startup.text = text('startupCommand');
    _identityId = meta['identityId'] as String?;
    _folderId = _entry?.folderId;
    _jumpHostId = meta['jumpHostId'] as String?;
    if (meta['identityMode'] == IdentityMode.perMember.name) {
      _identityMode = IdentityMode.perMember;
    }
    if (widget.hostId case final id?) {
      _forwards =
          AppScope.read(context).vault!.hostLookup(id)?.meta.forwards ??
          const [];
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _user, _tags, _notes, _startup]) {
      c.dispose();
    }
    super.dispose();
  }

  VaultEntry? get _entry => widget.hostId == null
      ? null
      : AppScope.read(context).vault!.entry(widget.hostId!);

  String? get _orgId => _entry?.orgId ?? widget.orgId;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    _problems.clear();
    if (_name.text.trim().isEmpty) _problems['name'] = l.fieldRequired;
    if (_address.text.trim().isEmpty) _problems['address'] = l.fieldRequired;
    final port = _port;
    String? optional(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    // Spreading the stored meta keeps the fields this editor does not show (forwards, jump host, unknown keys).
    final meta = {
      'schemaVersion': 1,
      ...?_entry?.meta,
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
      'forwards': [
        for (final f in _forwards ?? const <PortForward>[]) f.toJson(),
      ],
      'jumpHostId': _jumpHostId,
      'identityMode': _identityMode.name,
    };
    // written only when set
    if (_forwards?.isEmpty ?? true) meta.remove('forwards');
    if (_jumpHostId == null) meta.remove('jumpHostId');
    if (port == null) meta.remove('port'); // inherited
    if (_orgId == null || _identityMode == IdentityMode.shared) {
      meta.remove('identityMode');
    }
    if (_problems.isEmpty) {
      try {
        HostMeta.fromJson(meta);
      } on FormatException catch (e) {
        _problems[_fieldOf(e)] = l.fieldInvalid;
      }
    }
    if (_problems.isNotEmpty) return setState(() => _shakes++);
    await run(() async {
      final isNew = widget.hostId == null;
      await state.saveItem(
        type: 'host',
        id: widget.hostId,
        orgId: _orgId,
        folderId: _folderId,
        meta: meta,
      );
      if (isNew) state.emit(HostCreated(name: _name.text.trim()));
      widget.onClose?.call();
    });
  }

  // A `host.<field>: ...` message marks that field; anything else marks the name.
  static String _fieldOf(FormatException e) =>
      RegExp(r'^host\.(\w+)').firstMatch(e.message)?.group(1) ?? 'name';

  Future<void> _trash() async {
    final state = AppScope.read(context);
    await state.trashItem(widget.hostId!);
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
      final decoration = InputDecoration(
        hintText: inherits && resolvedValue != null ? '$resolvedValue' : null,
      );
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
          style: mono ? monoField : null,
          decoration: editable
              ? decoration
              : readOnlyDecoration(context, decoration),
        ),
      );
    }

    final orgId = _orgId;
    final identities = vault
        .ofKind(ItemKind.identity)
        .where((e) => e.state == EntryState.ok && e.orgId == orgId)
        .toList();
    final folders = vault
        .ofKind(ItemKind.folder)
        .where((e) => e.state == EntryState.ok && e.orgId == orgId)
        .toList();
    final folderName = vault.entry(_folderId ?? '')?.name;
    final readOnly = state.sync?.readOnly ?? true;
    return UfShake(
      shakes: _shakes,
      child: EditorFrame(
        title: entry?.name ?? l.treeNewHost,
        crumb: [vaultNameOf(l, state, orgId), ?folderName].join(' / '),
        notice: notice,
        onClose: widget.onClose,
        onConnect: switch (widget.hostId) {
          final id? when entry?.state == EntryState.ok => () => state.connect(
            id,
          ),
          _ => null,
        },
        tabs: [
          (
            l.inspectorTabForwards,
            [
              ForwardsEditor(
                forwards: _forwards ?? const [],
                enabled: editable,
                onChanged: (forwards) => setState(() => _forwards = forwards),
              ),
            ],
          ),
          if ((orgId, _folderId) case (final org?, final folder?)
              when widget.hostId != null)
            (l.inspectorTabAccess, [AccessTab(orgId: org, folderId: folder)]),
          if (state.serverHas(Flag.itemHistory) && widget.hostId != null)
            (
              l.itemHistory,
              [ItemHistoryPanel.embedded(itemId: widget.hostId!)],
            ),
        ],
        save: editable
            ? FilledButton(
                key: const Key('host-save'),
                onPressed: readOnly || _forwards == null ? null : _save,
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
          Column(
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
                    child: UfField(
                      label: l.hostPort,
                      source: _port == null ? source('port') : null,
                      error: _problems['port'],
                      child: UfNumberField(
                        key: const Key('host-port'),
                        value: _port,
                        min: 1,
                        width: double.infinity,
                        placeholder: resolved?.port,
                        onChanged: editable
                            ? (port) => setState(() => _port = port)
                            : null,
                      ),
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
          entryPicker(
            key: 'host-identity',
            label: l.hostIdentity,
            none: l.hostDefault,
            entries: identities,
            value: _identityId,
            source: _identityId == null ? source('identityId') : null,
            onChanged: editable ? (v) => setState(() => _identityId = v) : null,
          ),
          if (orgId != null)
            Column(
              key: const Key('host-identity-mode'),
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                for (final (mode, label) in [
                  (IdentityMode.shared, l.hostIdentityShared),
                  (IdentityMode.perMember, l.hostIdentityPerMember),
                ])
                  UfRadio<IdentityMode>(
                    key: Key('identity-mode-${mode.name}'),
                    value: mode,
                    groupValue: _identityMode,
                    label: label,
                    onChanged: editable
                        ? (mode) => setState(() => _identityMode = mode)
                        : null,
                  ),
              ],
            ),
          if (orgId != null &&
              _identityMode == IdentityMode.perMember &&
              widget.hostId != null)
            HostBindingField(hostId: widget.hostId!),
          JumpHostPicker(
            key: const Key('jump-picker'),
            hostId: widget.hostId,
            folderId: _folderId,
            value: _jumpHostId,
            inheritedId: resolved?.jumpHostId,
            inheritedFrom: switch (resolved?.sources['jumpHostId']) {
              null || 'default' || 'host' => null,
              final String folder => vault.entry(folder)?.name,
            },
            onChanged: editable ? (v) => setState(() => _jumpHostId = v) : null,
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
          if (problem case final error?) UfErrorLine(error),
        ],
      ),
    );
  }
}
