// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/buttons.dart';
import '../../design/choices.dart';
import '../../design/feedback.dart';
import '../../design/field.dart';
import '../../design/inputs.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../vault/vault.dart';
import '../busy_action.dart';
import '../history/item_history_panel.dart';
import '../keychain/identity_forms.dart';
import 'access_tab.dart';
import 'editor_frame.dart';
import 'forwards_editor.dart';
import 'host_binding_field.dart';
import 'jump_host_picker.dart';

part 'host_form_fields.dart';

/// Edits a host; empty port, user and key show the inherited value and where it comes from. A host moves
/// between folders by dragging it in the tree.
class HostEditorPanel extends StatefulWidget {
  const HostEditorPanel({
    super.key,
    this.hostId,
    this.orgId,
    this.folderId,
    this.onClose,
  });

  /// Null for a new host.
  final String? hostId;

  /// Org of a new host; null for the personal vault.
  final String? orgId;

  /// Folder of a new host; null for the vault's root.
  final String? folderId;
  final VoidCallback? onClose;

  @override
  State<HostEditorPanel> createState() => _HostEditorPanelState();
}

class _HostEditorPanelState extends State<HostEditorPanel>
    with BusyAction, _HostFormFields {
  // Null while a forward row has a problem.
  List<PortForward>? _forwards = const [];

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
    _folderId = _entry?.folderId ?? widget.folderId;
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
    if (port == null) meta.remove('port');
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
      await state.orgs!.saveItem(
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
    await run(() async {
      await state.orgs!.trashItem(widget.hostId!);
      widget.onClose?.call();
    });
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
    final folderName = vault.entry(_folderId ?? '')?.name;
    final readOnly = state.sync?.isReadOnly ?? true;
    return UfShake(
      shakes: _shakes,
      child: EditorFrame(
        title: entry?.name ?? l.treeNewHost,
        crumb: [vaultNameOf(l, state, _orgId), ?folderName].join(' / '),
        notice: notice,
        onClose: widget.onClose,
        onConnect: switch (widget.hostId) {
          final id? when entry?.state == EntryState.ok =>
            () => state.connections.connect(id),
          _ => null,
        },
        tabs: _tabs(l, state, editable: editable),
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
          _addressFields(l, editable: editable, resolved: resolved),
          ..._identityFields(l, editable: editable, resolved: resolved),
          ..._placementFields(editable: editable, resolved: resolved),
          ..._detailFields(l, editable: editable),
          if (problem case final error?) UfErrorLine(error),
        ],
      ),
    );
  }

  List<(String, List<Widget>)> _tabs(
    AppLocalizations l,
    AppState state, {
    required bool editable,
  }) => [
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
    if ((_orgId, _folderId) case (final org?, final folder?)
        when widget.hostId != null)
      (l.inspectorTabAccess, [AccessTab(orgId: org, folderId: folder)]),
    if (state.serverInfo.has(Flag.itemHistory) && widget.hostId != null)
      (l.itemHistory, [ItemHistoryPanel.embedded(itemId: widget.hostId!)]),
  ];
}
