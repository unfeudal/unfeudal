// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/choices.dart';
import '../../design/empty_state.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/inputs.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/toast.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../keys/key_tools.dart';
import '../../orgs/host_binding.dart';
import '../../vault/vault.dart';
import '../form_dialog.dart';
import '../history/item_history_panel.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';

/// Where the keychain reads and writes: the personal vault, or one org folder (shared identities).
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
  }) => state.saveItem(
    type: 'identity',
    id: id,
    orgId: _orgId,
    folderId: folderId,
    meta: meta,
    secret: secret,
  );

  Future<void> trash(String id) => folderId == null
      ? state.vault!.trashItem(id)
      : state.orgs!.writer.trash(id);
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
  /// Where new keys of an org vault go; the personal vault has a single place.
  String? _folderId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final vault = state.vault!;
    final orgId = state.orgs?.selected;
    final vaultName = vaultNameOf(l, state, orgId);
    final orgFolders = [
      if (orgId != null)
        for (final e in vault.ofKind(ItemKind.folder))
          if (e.orgId == orgId && e.state == EntryState.ok) e,
    ]..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    if (!orgFolders.any((e) => e.id == _folderId)) {
      _folderId = orgFolders.firstOrNull?.id; // the vault or the folder changed
    }
    final place = _Place(state, _folderId);
    final serverReadOnly = state.sync?.readOnly ?? true;
    final readOnly =
        serverReadOnly ||
        (orgId != null && _folderId == null) ||
        !place.editable;
    final identities =
        vault
            .ofKind(ItemKind.identity)
            .where(
              (e) =>
                  e.state == EntryState.ok &&
                  // an org vault without folders holds no key
                  (orgId == null || _folderId != null) &&
                  place.holds(e),
            )
            .toList()
          ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    // personal keys bound to this org's hosts: shown here, edited in the personal vault
    final linked = orgId == null
        ? const <VaultEntry>[]
        : ({
              for (final h in vault.ofKind(ItemKind.host))
                if (h.orgId == orgId) ?bindingFor(vault, h.id),
            }.map(vault.entry).nonNulls.toList()
            ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? '')));
    Future<void> form(
      String title,
      List<FormDialogField> fields,
      String saveKey,
      Future<void> Function(Map<String, String>) save, {
      Map<String, String> initial = const {},
    }) => showUfDialog<bool>(
      context,
      (_) => FormDialog(
        title: title,
        fields: fields,
        saveKey: saveKey,
        saveLabel: l.keySave,
        onSave: save,
        initial: initial,
      ),
    );
    Widget row(VaultEntry e, {required bool editable}) => _IdentityRow(
      entry: e,
      readOnly: !editable,
      onRename: () => form(
        l.keyRename,
        [FormDialogField('identity-name', l.keyName)],
        'identity-name-save',
        (v) => place.save(
          IdentityMeta.fromJson({
            ...?e.meta,
            'name': v['identity-name']!.trim(),
          }).toJson(),
          id: e.id,
        ),
        initial: {'identity-name': e.name ?? ''},
      ),
      onDelete: () => _confirmTrash(context, place, e),
      onReveal: canReveal(state, e) ? () => _reveal(context, e) : null,
      onHistory: state.serverHas('item_history')
          ? () => showUfDialog<void>(
              context,
              (_) => ItemHistoryPanel(itemId: e.id),
            )
          : null,
    );
    final caption = Theme.of(context).textTheme.labelSmall!
        .copyWith(color: colors.muted);
    return ManageFrame(
      title: l.keychainTitle,
      subtitle: vaultName,
      onBack: widget.onBack,
      actions: [
        FilledButton.icon(
          key: const Key('key-generate'),
          icon: const Icon(UfIcons.plus),
          onPressed: readOnly
              ? null
              : () => form(
                  l.keyGenerate,
                  [
                    FormDialogField('gen-name', l.keyName),
                    FormDialogField(
                      'gen-passphrase',
                      l.keyPassphrase,
                      kind: FormFieldKind.secret,
                    ),
                    FormDialogField(
                      'gen-type-rsa',
                      l.keyTypeRsa,
                      kind: FormFieldKind.toggle,
                      offLabel: l.keyTypeEd25519,
                    ),
                  ],
                  'gen-save',
                  (v) => _generate(place, v),
                ),
          label: Text(l.keyGenerate),
        ),
        OutlinedButton(
          key: const Key('key-import'),
          onPressed: readOnly
              ? null
              : () => form(
                  l.keyImport,
                  [
                    FormDialogField('import-name', l.keyName),
                    FormDialogField(
                      'import-pem',
                      l.keyPem,
                      lines: 6,
                      mono: true,
                    ),
                    FormDialogField(
                      'import-passphrase',
                      l.keyPassphrase,
                      kind: FormFieldKind.secret,
                    ),
                  ],
                  'import-save',
                  (v) => _import(place, v),
                ),
          child: Text(l.keyImport),
        ),
        OutlinedButton(
          key: const Key('key-password'),
          onPressed: readOnly
              ? null
              : () => form(
                  l.keyPassword,
                  [
                    FormDialogField('pw-name', l.keyName),
                    FormDialogField(
                      'pw-value',
                      l.keyKindPassword,
                      kind: FormFieldKind.secret,
                    ),
                  ],
                  'pw-save',
                  (v) => _password(place, v),
                ),
          child: Text(l.keyPassword),
        ),
      ],
      maxWidth: identities.isEmpty && linked.isEmpty && orgFolders.isEmpty
          ? null
          : 980,
      child: identities.isEmpty && linked.isEmpty && orgFolders.isEmpty
          ? EmptyState(title: l.keychainTitle, body: l.keychainEmpty)
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (orgFolders.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 320,
                      child: UfField(
                        label: l.keychainPlace,
                        child: UfSelect<String?>(
                          key: const Key('keychain-place'),
                          value: _folderId,
                          options: [
                            for (final f in orgFolders)
                              UfOption(
                                f.id,
                                f.name ?? '',
                                key: Key('keychain-place-${f.id}'),
                              ),
                          ],
                          onChanged: (v) => setState(() => _folderId = v),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 4),
                  child: Text(
                    l.keychainOf(
                      orgFolders
                              .where((f) => f.id == _folderId)
                              .firstOrNull
                              ?.name ??
                          vaultName,
                    ),
                    style: caption,
                  ),
                ),
                if (identities.isEmpty)
                  Text(
                    l.keychainEmpty,
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: colors.muted),
                  ),
                for (final e in identities)
                  row(e, editable: !serverReadOnly && place.editable),
                if (linked.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 4),
                    child: Text(l.keychainLinked(vaultName), style: caption),
                  ),
                  for (final e in linked)
                    KeyedSubtree(
                      key: Key('identity-linked-${e.id}'),
                      child: _IdentityRow(entry: e, readOnly: true),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l.keychainLinkedNote,
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  /// Shows the secret once per opening and reports that it was shown.
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

  static Future<void> _generate(_Place place, Map<String, String> v) async {
    final passphrase = v['gen-passphrase']!.isEmpty
        ? null
        : v['gen-passphrase'];
    final name = v['gen-name']!.trim();
    final key = v['gen-type-rsa'] == 'true'
        ? await generateRsa4096(comment: name, passphrase: passphrase)
        : await generateEd25519(comment: name, passphrase: passphrase);
    await _savePrivateKey(
      place,
      name,
      key.privateKeyPem,
      passphrase,
      key.publicKey,
    );
  }

  /// The key is read (and its passphrase checked) before anything is stored; the original text is kept.
  static Future<void> _import(_Place place, Map<String, String> v) async {
    final passphrase = v['import-passphrase']!.isEmpty
        ? null
        : v['import-passphrase'];
    final pem = v['import-pem']!.trim();
    final publicKey = publicKeyOf(pem, passphrase: passphrase);
    await _savePrivateKey(
      place,
      v['import-name']!.trim(),
      pem,
      passphrase,
      publicKey,
    );
  }

  static Future<void> _savePrivateKey(
    _Place place,
    String name,
    String pem,
    String? passphrase,
    String publicKey,
  ) => place.save(
    IdentityMeta(
      name: name,
      kind: IdentityKind.privateKey,
      publicKey: publicKey,
    ).toJson(),
    secret: IdentitySecret(
      kind: IdentityKind.privateKey,
      privateKeyPem: pem,
      passphrase: passphrase,
    ).toJson(),
  );

  static Future<void> _password(_Place place, Map<String, String> v) =>
      place.save(
        IdentityMeta(
          name: v['pw-name']!.trim(),
          kind: IdentityKind.password,
        ).toJson(),
        secret: IdentitySecret(
          kind: IdentityKind.password,
          password: v['pw-value'],
        ).toJson(),
      );

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

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.entry,
    required this.readOnly,
    this.onRename,
    this.onDelete,
    this.onReveal,
    this.onHistory,
  });

  final VaultEntry entry;
  final bool readOnly;

  /// Null on a linked key: it is edited in the personal vault.
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  /// Null hides the button (no reveal flag, or no reveal right on the folder).
  final VoidCallback? onReveal;

  /// Null hides the button (no item history on this server).
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final publicKey = entry.meta?['publicKey'] as String?;
    final isKey = entry.meta?['kind'] == IdentityKind.privateKey.name;
    final linked = onRename == null;
    return ItemRow(
      icon: isKey ? UfIcons.key : UfIcons.password,
      title: entry.name ?? '',
      subtitle: publicKey ?? (isKey ? l.keyKindPrivateKey : l.keyKindPassword),
      monoSubtitle: publicKey != null,
      trailing: [
        if (linked) UfTag(l.vaultPersonal),
        if (publicKey != null)
          IconButton(
            key: Key('identity-copy-${entry.id}'),
            tooltip: l.keyCopyPublic,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: publicKey));
              if (context.mounted) showUfToast(context, l.keyCopied);
            },
            icon: const Icon(UfIcons.copy),
          ),
        if (onReveal != null)
          IconButton(
            key: Key('identity-reveal-${entry.id}'),
            tooltip: l.identityReveal,
            onPressed: onReveal,
            icon: const Icon(UfIcons.eye),
          ),
        if (onHistory != null)
          IconButton(
            key: Key('identity-history-${entry.id}'),
            tooltip: l.itemHistory,
            onPressed: onHistory,
            icon: const Icon(UfIcons.clockCounterClockwise),
          ),
        if (!linked) ...[
          IconButton(
            key: Key('identity-rename-${entry.id}'),
            tooltip: l.keyRename,
            onPressed: readOnly ? null : onRename,
            icon: const Icon(UfIcons.pencil),
          ),
          IconButton(
            key: Key('identity-delete-${entry.id}'),
            tooltip: l.keyDelete,
            onPressed: readOnly ? null : onDelete,
            icon: const Icon(UfIcons.trash),
          ),
        ],
      ],
    );
  }
}

/// The password, or the private key and its passphrase; a copy is wiped from the clipboard after a minute.
class _RevealDialog extends StatefulWidget {
  const _RevealDialog({required this.name, required this.secret});

  final String name;
  final IdentitySecret secret;

  @override
  State<_RevealDialog> createState() => _RevealDialogState();
}

class _RevealDialogState extends State<_RevealDialog> {
  Timer? _clear;
  String? _copied;

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _copied = text;
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 60), _wipe);
  }

  /// Clears the clipboard only if it still holds the copied secret.
  Future<void> _wipe() async {
    _clear?.cancel();
    _clear = null;
    final now = await Clipboard.getData(Clipboard.kTextPlain);
    if (now?.text == _copied) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  @override
  void dispose() {
    if (_clear != null) unawaited(_wipe());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final s = widget.secret;
    Widget field(String value) => UfReadOnlyField(
      value: value,
      mono: true,
      onCopy: () => _copy(value),
      copyTooltip: material.copyButtonLabel,
    );
    return UfDialog(
      title: l.identityRevealTitle(widget.name),
      actions: [
        OutlinedButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(material.closeButtonLabel),
        ),
      ],
      children: [
        if (s.password case final password?) field(password),
        if (s.passphrase case final passphrase?) field(passphrase),
        if (s.privateKeyPem case final pem?) field(pem),
      ],
    );
  }
}
