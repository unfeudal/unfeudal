// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/empty_state.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../terminal/snippet_insertion.dart';
import '../../vault/org_writer.dart';
import '../../vault/snippet_store.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
import '../history/item_history_panel.dart';
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
    final tab = state.activeSession;
    final canInsert = tab?.state == SealState.connected;
    final snippets = [
      for (final s in store.list(query: _query.text))
        if (vault.entry(s.id)?.orgId == orgId) s,
    ];
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);

    Future<void> insert(SnippetMeta meta) async {
      await insertSnippet(
        tab!,
        meta.command,
        confirm: () => confirmUnsafeMultiline(context),
      );
    }

    Future<void> delete(String id, SnippetMeta meta) async {
      final yes = await confirmDanger(
        context,
        question: l.snippetDeleteConfirm(meta.name),
        action: l.snippetDelete,
      );
      if (yes) await store.delete(id);
    }

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
          SizedBox(
            width: 360,
            child: TextField(
              key: const Key('snippets-search'),
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l.snippetsSearch,
                prefixIcon: Icon(
                  UfIcons.magnifyingGlass,
                  size: 14,
                  color: colors.muted,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
              ),
            ),
          ),
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
                : ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: [
                      for (final (:id, :meta) in snippets)
                        if (!readOnly && canEditEntry(state, vault.entry(id)!)
                            case final editable)
                          ItemRow(
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
                                onPressed: canInsert
                                    ? () => insert(meta)
                                    : null,
                                child: Text(l.snippetInsert),
                              ),
                              IconButton(
                                key: Key('snippet-edit-$id'),
                                tooltip: l.snippetEdit,
                                onPressed: editable
                                    ? () => _edit(
                                        context,
                                        store,
                                        orgId,
                                        id: id,
                                        meta: meta,
                                      )
                                    : null,
                                icon: const Icon(UfIcons.pencil),
                              ),
                              IconButton(
                                key: Key('snippet-delete-$id'),
                                tooltip: l.snippetDelete,
                                onPressed: editable
                                    ? () => delete(id, meta)
                                    : null,
                                icon: const Icon(UfIcons.trash),
                              ),
                            ],
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
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

  /// Where a new snippet goes: an org folder of the shown vault, or the personal vault (null).
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
            none: l.vaultPersonal,
            entries: folders,
            value: _folderId,
            onChanged: (v) => setState(() => _folderId = v),
          ),
      ],
    );
  }
}
