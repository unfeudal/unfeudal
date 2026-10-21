// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/choices.dart';
import '../../design/dialog.dart';
import '../../design/empty_state.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/inputs.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/toast.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../orgs/host_binding.dart';
import '../../vault/vault.dart';
import '../form_dialog.dart';
import '../history/item_history_panel.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';
import '../secret_clipboard.dart';
import 'identity_forms.dart';

part 'identity_row.dart';
part 'keychain_list.dart';
part 'place_picker.dart';

// Where the keychain reads and writes: the personal vault, or one org folder (shared identities).
class _Place {
  _Place(this.state, this.folderId);

  final AppState state;
  final String? folderId;

  VaultEntry? get _folder =>
      folderId == null ? null : state.vault!.entry(folderId!);

  String? get _orgId => folderId == null ? null : _folder!.orgId!;

  bool get editable =>
      folderId == null ||
      (state.orgs?.writer.canEdit(_orgId!, folderId) ?? false);

  bool holds(VaultEntry e) =>
      folderId == null ? e.orgId == null : e.folderId == folderId;

  Future<void> save(
    Map<String, Object?> meta, {
    Map<String, Object?>? secret,
    String? id,
  }) => state.orgs!.saveItem(
    type: 'identity',
    id: id,
    orgId: _orgId,
    folderId: folderId,
    meta: meta,
    secret: secret,
  );

  Future<void> trash(String id) => state.orgs!.trashItem(id);
}

/// The selected vault's SSH keys and passwords: generate, import, add a password, copy a public key, rename,
/// trash; an org vault keeps them per folder and lists the personal keys bound to its hosts, read-only.
class KeychainScreen extends StatefulWidget {
  const KeychainScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<KeychainScreen> createState() => _KeychainScreenState();
}

class _KeychainScreenState extends State<KeychainScreen> {
  // Where new keys of an org vault go; the personal vault has a single place.
  String? _folderId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final orgId = state.orgs?.selected;
    final vaultName = vaultNameOf(l, state, orgId);
    final orgFolders = [
      if (orgId != null) ...vault.usableOfKind(ItemKind.folder, orgId: orgId),
    ]..sort(byName);
    // the vault or the folder changed
    if (!orgFolders.any((e) => e.id == _folderId)) {
      _folderId = orgFolders.firstOrNull?.id;
    }
    final place = _Place(state, _folderId);
    final serverReadOnly = state.sync?.isReadOnly ?? true;
    final readOnly =
        serverReadOnly ||
        (orgId != null && _folderId == null) ||
        !place.editable;
    final identities = _identitiesIn(vault, place, orgId: orgId);
    final linked = _linkedKeys(vault, orgId);
    final empty = identities.isEmpty && linked.isEmpty && orgFolders.isEmpty;
    return ManageFrame(
      title: l.keychainTitle,
      subtitle: vaultName,
      onBack: widget.onBack,
      actions: [
        FilledButton.icon(
          key: const Key('key-generate'),
          icon: const Icon(UfIcons.plus),
          onPressed: readOnly ? null : () => _openGenerate(place),
          label: Text(l.keyGenerate),
        ),
        OutlinedButton(
          key: const Key('key-import'),
          onPressed: readOnly ? null : () => _openImport(place),
          child: Text(l.keyImport),
        ),
        OutlinedButton(
          key: const Key('key-password'),
          onPressed: readOnly ? null : () => _openPassword(place),
          child: Text(l.keyPassword),
        ),
      ],
      maxWidth: empty ? null : 980,
      child: empty
          ? EmptyState(title: l.keychainTitle, body: l.keychainEmpty)
          : _KeychainList(
              orgFolders: orgFolders,
              folderId: _folderId,
              onFolderChanged: (v) => setState(() => _folderId = v),
              vaultName: vaultName,
              rows: [
                for (final e in identities)
                  _row(e, place: place, readOnly: readOnly),
              ],
              linked: linked,
            ),
    );
  }

  static List<VaultEntry> _identitiesIn(
    Vault vault,
    _Place place, {
    required String? orgId,
  }) =>
      vault
          .ofKind(ItemKind.identity)
          .where(
            (e) =>
                e.state == EntryState.ok &&
                // an org vault without folders holds no key
                (orgId == null || place.folderId != null) &&
                place.holds(e),
          )
          .toList()
        ..sort(byName);

  // Personal keys bound to this org's hosts: shown here, edited in the personal vault.
  static List<VaultEntry> _linkedKeys(Vault vault, String? orgId) =>
      orgId == null
      ? const <VaultEntry>[]
      : ({
          for (final h in vault.ofKind(ItemKind.host))
            if (h.orgId == orgId) ?bindingFor(vault, h.id),
        }.map(vault.entry).nonNulls.toList()..sort(byName));

  Widget _row(VaultEntry e, {required _Place place, required bool readOnly}) {
    final state = AppScope.read(context);
    return _IdentityRow(
      entry: e,
      readOnly: readOnly,
      onRename: () => _openRename(place, e),
      onDelete: () => _confirmTrash(context, place, e),
      onReveal: state.serverInfo.has(Flag.reveal) && state.orgs!.canReveal(e)
          ? () => _reveal(context, e)
          : null,
      onHistory: state.serverInfo.has(Flag.itemHistory)
          ? () => showUfDialog<void>(
              context,
              (_) => ItemHistoryPanel(itemId: e.id),
            )
          : null,
    );
  }

  Future<void> _form({
    required String title,
    required List<FormDialogField> fields,
    required String saveKey,
    required Future<void> Function(Map<String, String>) onSave,
    Map<String, String> initial = const {},
  }) => showUfDialog<bool>(
    context,
    (_) => FormDialog(
      title: title,
      fields: fields,
      saveKey: saveKey,
      saveLabel: AppLocalizations.of(context).keySave,
      onSave: onSave,
      initial: initial,
    ),
  );

  Future<void> _openRename(_Place place, VaultEntry e) {
    final l = AppLocalizations.of(context);
    return _form(
      title: l.keyRename,
      fields: [FormDialogField('identity-name', l.keyName)],
      saveKey: 'identity-name-save',
      onSave: (v) => place.save(
        IdentityMeta.fromJson({...?e.meta, 'name': v['identity-name']!.trim()})
            .toJson(),
        id: e.id,
      ),
      initial: {'identity-name': e.name ?? ''},
    );
  }

  IdentityPlace _identityPlace(_Place place) =>
      (orgId: place._orgId, folderId: place.folderId);

  Future<void> _openGenerate(_Place place) =>
      showGenerateKey(context, _identityPlace(place));

  Future<void> _openImport(_Place place) =>
      showImportKey(context, _identityPlace(place));

  Future<void> _openPassword(_Place place) =>
      showAddPassword(context, _identityPlace(place));

  // Shows the secret once per opening and reports that it was shown.
  static Future<void> _reveal(BuildContext context, VaultEntry e) async {
    final state = AppScope.read(context);
    final secret = await state.vault!.identitySecret(e.id);
    if (secret == null || !context.mounted) return;
    state.emit(SecretRevealed(itemId: e.id));
    await showUfDialog<void>(
      context,
      (_) => _RevealDialog(name: e.name ?? '', secret: secret),
    );
  }

  static Future<void> _confirmTrash(
    BuildContext context,
    _Place place,
    VaultEntry e,
  ) async {
    final l = AppLocalizations.of(context);
    final yes = await confirmDanger(
      context,
      question: l.keyDeleteConfirm(e.name ?? ''),
      action: l.keyDelete,
    );
    if (yes) await place.trash(e.id);
  }
}
