// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/empty_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../terminal/snippet_insertion.dart';
import '../../terminal/terminal_session.dart';
import '../../vault/org_writer.dart';
import '../../vault/snippet_store.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import '../fields.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';
import '../terminal/multiline_dialog.dart';

/// The selected vault's snippets: search, create, edit, trash, and insert into the active terminal (never run).
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
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
    final vault = state.vault!;
    final store = SnippetStore(vault, writer: state.orgs?.writer);
    final orgId = state.orgs?.selected;
    final vaultName = vaultNameOf(l, state, orgId);
    final readOnly = state.sync?.readOnly ?? true;
    final tab = state.connections.activeSession;
    final canInsert = tab?.state == SealState.connected;
    final snippets = [
      for (final s in store.list(query: _query.text))
        if (vault.entry(s.id)?.orgId == orgId) s,
    ];
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    return ManageFrame(
      title: l.snippetsTitle,
      subtitle: vaultName,
      onBack: widget.onBack,
      actions: [
        FilledButton.icon(
          key: const Key('snippet-new'),
          icon: const Icon(UfIcons.plus),
          onPressed: readOnly ? null : () => _edit(context, store, orgId),
          label: Text(l.snippetNew),
        ),
      ],
      maxWidth: 980,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _SnippetSearch(controller: _query, onChanged: () => setState(() {})),
          Text(canInsert ? l.snippetsNote : l.snippetNoTerminal, style: muted),
          Expanded(
            child: snippets.isEmpty && _query.text.isEmpty
                ? EmptyState(
                    title: l.snippetsTitle,
                    body: l.snippetsEmpty,
                    primary: readOnly
                        ? null
                        : (l.snippetNew, () => _edit(context, store, orgId)),
                  )
                : _snippetList(
                    store,
                    orgId,
                    snippets: snippets,
                    readOnly: readOnly,
                    insertInto: canInsert ? tab : null,
                  ),
          ),
        ],
      ),
    );
  }

  // A null [insertInto] disables Insert: no terminal is connected.
  Widget _snippetList(
    SnippetStore store,
    String? orgId, {
    required List<({String id, SnippetMeta meta})> snippets,
    required bool readOnly,
    required TerminalSession? insertInto,
  }) {
    final state = AppScope.read(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        for (final (:id, :meta) in snippets)
          if (!readOnly && state.orgs!.canEditEntry(state.vault!.entry(id)!)
              case final editable)
            _SnippetRow(
              id: id,
              meta: meta,
              onInsert: switch (insertInto) {
                final tab? => () => _insert(tab, meta),
                null => null,
              },
              onEdit: editable
                  ? () => _edit(context, store, orgId, id: id, meta: meta)
                  : null,
              onDelete: editable ? () => _delete(store, id, meta) : null,
            ),
      ],
    );
  }

  Future<void> _insert(TerminalSession tab, SnippetMeta meta) async {
    await insertSnippet(
      tab,
      meta.command,
      confirm: () => confirmUnsafeMultiline(context),
    );
  }

  Future<void> _delete(SnippetStore store, String id, SnippetMeta meta) async {
    final l = AppLocalizations.of(context);
    final yes = await confirmDanger(
      context,
      question: l.snippetDeleteConfirm(meta.name),
      action: l.snippetDelete,
    );
    if (yes) await store.delete(id);
  }

  Future<void> _edit(
    BuildContext context,
    SnippetStore store,
    String? orgId, {
    String? id,
    SnippetMeta? meta,
  }) async {
    await showUfDialog<void>(
      context,
      (dialog) =>
          _SnippetEditor(store: store, orgId: orgId, id: id, meta: meta),
    );
    if (mounted) setState(() {});
  }
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({
    required this.store,
    required this.orgId,
    this.id,
    this.meta,
  });

  final SnippetStore store;

  /// The vault the section shows; a new snippet goes to one of its folders the user can edit.
  final String? orgId;
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

  // Where a new snippet goes: an org folder of the shown vault, or the personal vault (null).
  late String? _folderId = _folders.firstOrNull?.id;

  List<VaultEntry> get _folders {
    final writer = widget.store.writer;
    if (widget.id != null || writer == null || widget.orgId == null) {
      return const [];
    }
    return [
      for (final e in widget.store.vault.ofKind(ItemKind.folder))
        if (e.orgId == widget.orgId && writer.canEdit(e.orgId!, e.id)) e,
    ];
  }

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
          // Unlike the name, the command is stored as typed, untrimmed.
          command: _command.text,
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
    final folders = _folders;
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
        keyedField(
          'snippet-name',
          _name,
          l.snippetName,
          error: _problems['name'],
        ),
        keyedField(
          'snippet-command',
          _command,
          l.snippetCommand,
          minLines: 3,
          maxLines: 8,
          mono: true,
          error: _problems['command'],
        ),
        keyedField('snippet-tags', _tags, l.snippetTags),
        if (folders.isNotEmpty)
          entryPicker(
            key: 'snippet-location',
            label: l.snippetLocation,
            none: l.vaultPersonal,
            entries: folders,
            value: _folderId,
            onChanged: (v) => setState(() => _folderId = v),
          ),
      ],
    );
  }
}

class _SnippetSearch extends StatelessWidget {
  const _SnippetSearch({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return SizedBox(
      width: 360,
      child: TextField(
        key: const Key('snippets-search'),
        controller: controller,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          hintText: l.snippetsSearch,
          prefixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
            child: Icon(UfIcons.magnifyingGlass, size: 14, color: colors.muted),
          ),
          prefixIconConstraints: const BoxConstraints(),
        ),
      ),
    );
  }
}

class _SnippetRow extends StatelessWidget {
  const _SnippetRow({
    required this.id,
    required this.meta,
    required this.onInsert,
    required this.onEdit,
    required this.onDelete,
  });

  final String id;
  final SnippetMeta meta;
  final VoidCallback? onInsert;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ItemRow(
      key: Key('snippet-$id'),
      icon: UfIcons.terminal,
      title: meta.name,
      subtitle: meta.command.trimLeft().split('\n').first,
      monoSubtitle: true,
      trailing: [
        for (final tag in meta.tags.take(3)) UfTag(tag),
        OutlinedButton(
          key: Key('snippet-insert-$id'),
          style: smallButton,
          onPressed: onInsert,
          child: Text(l.snippetInsert),
        ),
        IconButton(
          key: Key('snippet-edit-$id'),
          tooltip: l.snippetEdit,
          onPressed: onEdit,
          icon: const Icon(UfIcons.pencil),
        ),
        IconButton(
          key: Key('snippet-delete-$id'),
          tooltip: l.snippetDelete,
          onPressed: onDelete,
          icon: const Icon(UfIcons.trash),
        ),
      ],
    );
  }
}
