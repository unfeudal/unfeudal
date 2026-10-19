// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/motion.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../terminal/snippet_insertion.dart';
import '../../vault/org_writer.dart';
import '../../vault/snippet_store.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import '../history/item_history_panel.dart';
import '../hosts/editor_frame.dart';
import '../terminal/multiline_dialog.dart';

/// Synced snippets: search, create, edit, trash, and insert into the active terminal (never run).
class SnippetsPanel extends StatefulWidget {
  const SnippetsPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<SnippetsPanel> createState() => _SnippetsPanelState();
}

class _SnippetsPanelState extends State<SnippetsPanel> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final store = SnippetStore(state.vault!, writer: state.orgs?.writer);
    final readOnly = state.sync?.readOnly ?? true;
    final tab = state.tabs.isEmpty
        ? null
        : state.tabs[state.activeTab.clamp(0, state.tabs.length - 1)];
    final canInsert = tab?.state == SealState.connected;
    final snippets = store.list(query: _query.text);
    final small = Theme.of(context).textTheme.labelSmall!;

    Future<void> insert(String id, SnippetMeta meta) async {
      final sent = await insertSnippet(
        tab!,
        meta.command,
        confirm: () => confirmUnsafeMultiline(context),
      );
      if (sent) state.emit(SnippetInserted(snippetId: id));
    }

    Future<void> delete(String id, SnippetMeta meta) async {
      final yes = await confirmDanger(
        context,
        question: l.snippetDeleteConfirm(meta.name),
        action: l.snippetDelete,
      );
      if (yes) await store.delete(id);
    }

    return EditorFrame(
      title: l.snippetsTitle,
      onClose: widget.onClose,
      children: [
        TextField(
          key: const Key('snippets-search'),
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: l.snippetsSearch),
        ),
        if (!canInsert)
          Text(l.snippetNoTerminal, style: small.copyWith(color: colors.muted)),
        if (snippets.isEmpty && _query.text.isEmpty)
          Text(l.snippetsEmpty, style: TextStyle(color: colors.muted)),
        for (final (:id, :meta) in snippets)
          if (!readOnly && canEditEntry(state, state.vault!.entry(id)!)
              case final editable)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(meta.name, style: TextStyle(color: colors.text)),
                if (meta.tags.isNotEmpty)
                  Text(
                    meta.tags.join(', '),
                    style: small.copyWith(color: colors.muted),
                  ),
                Text(
                  meta.command.trimLeft().split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontSize: 12, color: colors.muted),
                ),
                Row(
                  children: [
                    TextButton(
                      key: Key('snippet-insert-$id'),
                      onPressed: canInsert ? () => insert(id, meta) : null,
                      child: Text(l.snippetInsert),
                    ),
                    TextButton(
                      key: Key('snippet-edit-$id'),
                      onPressed: editable
                          ? () => _edit(context, store, id: id, meta: meta)
                          : null,
                      child: Text(l.snippetEdit),
                    ),
                    TextButton(
                      key: Key('snippet-delete-$id'),
                      onPressed: editable ? () => delete(id, meta) : null,
                      child: Text(l.snippetDelete),
                    ),
                  ],
                ),
              ],
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('snippet-new'),
            onPressed: readOnly ? null : () => _edit(context, store),
            child: Text(l.snippetNew),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    SnippetStore store, {
    String? id,
    SnippetMeta? meta,
  }) async {
    await showUfDialog<void>(
      context,
      (dialog) => _SnippetEditor(store: store, id: id, meta: meta),
    );
    if (mounted) setState(() {});
  }
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({required this.store, this.id, this.meta});

  final SnippetStore store;
  final String? id;
  final SnippetMeta? meta;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  late final _name = TextEditingController(text: widget.meta?.name ?? '');
  late final _command = TextEditingController(text: widget.meta?.command ?? '');
  late final _tags = TextEditingController(
    text: widget.meta?.tags.join(', ') ?? '',
  );
  final _problems = <String, String>{};

  /// A new snippet's org folder; null keeps it personal.
  String? _folderId;

  @override
  void dispose() {
    for (final c in [_name, _command, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    _problems.clear();
    if (_name.text.trim().isEmpty) _problems['name'] = l.fieldRequired;
    if (_command.text.trim().isEmpty) _problems['command'] = l.fieldRequired;
    if (_problems.isNotEmpty) return setState(() {});
    try {
      await widget.store.save(
        SnippetMeta(
          name: _name.text.trim(),
          command: _command.text, // stored as typed
          tags: [
            for (final t in _tags.text.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
          extra: widget.meta?.extra ?? const {},
        ),
        id: widget.id,
        target: switch (_folderId) {
          final folder? => OrgTarget(
            widget.store.vault.entry(folder)!.orgId!,
            folder,
          ),
          null => null,
        },
      );
      if (mounted) Navigator.pop(context);
    } on FormatException {
      setState(() => _problems['name'] = l.fieldInvalid);
    } on Exception catch (e) {
      setState(() => _problems['name'] = describeError(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final writer = widget.store.writer;
    // where a new snippet may go: org folders the user can edit
    final folders = widget.id != null || writer == null
        ? const <VaultEntry>[]
        : [
            for (final e in widget.store.vault.ofKind(ItemKind.folder))
              if (e.orgId != null && writer.canEdit(e.orgId!, e.id)) e,
          ];
    return UfDialog(
      width: 480,
      title: widget.id == null ? l.snippetNew : l.snippetEdit,
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context)),
        FilledButton(
          key: const Key('snippet-save'),
          onPressed: _save,
          child: Text(l.snippetSave),
        ),
      ],
      children: [
        UfField(
          label: l.snippetName,
          error: _problems['name'],
          child: TextField(key: const Key('snippet-name'), controller: _name),
        ),
        UfField(
          label: l.snippetCommand,
          error: _problems['command'],
          child: TextField(
            key: const Key('snippet-command'),
            controller: _command,
            minLines: 3,
            maxLines: 8,
            style: monoStyle.copyWith(fontSize: 13),
          ),
        ),
        UfField(
          label: l.snippetTags,
          child: TextField(key: const Key('snippet-tags'), controller: _tags),
        ),
        if (folders.isNotEmpty)
          entryPicker(
            key: 'snippet-location',
            label: l.snippetLocation,
            none: l.snippetPersonal,
            entries: folders,
            value: _folderId,
            onChanged: (v) => setState(() => _folderId = v),
          ),
      ],
    );
  }
}
