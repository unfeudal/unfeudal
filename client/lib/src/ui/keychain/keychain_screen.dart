// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/empty_state.dart';
import '../../design/dialog.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../keys/key_tools.dart';
import '../../vault/org_writer.dart';
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

  bool get editable =>
      folderId == null ||
      (state.orgs?.writer.canEdit(_folder!.orgId!, folderId) ?? false);

  bool holds(VaultEntry e) =>
      folderId == null ? e.orgId == null : e.folderId == folderId;

  Future<void> save(
    Map<String, Object?> meta, {
    Map<String, Object?>? secret,
    String? id,
  }) async {
    if (folderId == null) {
      await state.vault!.upsertItem(
        type: 'identity',
        id: id,
        meta: meta,
        secret: secret,
      );
    } else {
      await state.orgs!.writer.upsert(
        type: 'identity',
        id: id,
        target: OrgTarget(_folder!.orgId!, folderId),
        meta: meta,
        secret: secret,
      );
    }
  }

  Future<void> trash(String id) => folderId == null
      ? state.vault!.trashItem(id)
      : state.orgs!.writer.trash(id);
}

/// SSH keys and passwords: generate, import, add a password, copy a public key, rename, trash; personal, or
/// shared in an org folder.
class KeychainScreen extends StatefulWidget {
  const KeychainScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<KeychainScreen> createState() => _KeychainScreenState();
}

class _KeychainScreenState extends State<KeychainScreen> {
  String? _folderId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final orgFolders = [
      for (final e in vault.ofKind(ItemKind.folder))
        if (e.orgId != null && e.state == EntryState.ok) e,
    ];
    if (_folderId != null && !orgFolders.any((e) => e.id == _folderId)) {
      _folderId = null; // the folder left this vault
    }
    final place = _Place(state, _folderId);
    final readOnly = (state.sync?.readOnly ?? true) || !place.editable;
    final identities =
        vault
            .ofKind(ItemKind.identity)
            .where((e) => e.state == EntryState.ok && place.holds(e))
            .toList()
          ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
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
    return ManageFrame(
      title: l.keychainTitle,
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (orgFolders.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 320,
                child: entryPicker(
                  key: 'keychain-place',
                  label: l.keychainPlace,
                  none: l.vaultPersonal,
                  entries: orgFolders,
                  value: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('key-generate'),
                icon: const Icon(UfIcons.plus, size: 15),
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
          ),
          Expanded(
            child: identities.isEmpty
                ? EmptyState(title: l.keychainTitle, body: l.keychainEmpty)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: [
                      for (final e in identities)
                        _IdentityRow(
                          entry: e,
                          readOnly: readOnly,
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
                          onReveal: canReveal(state, e)
                              ? () => _reveal(context, e)
                              : null,
                          onHistory: state.serverHas('item_history')
                              ? () => showUfDialog<void>(
                                  context,
                                  (_) => ItemHistoryPanel(itemId: e.id),
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
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
    required this.onRename,
    required this.onDelete,
    this.onReveal,
    this.onHistory,
  });

  final VaultEntry entry;
  final bool readOnly;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// Null hides the button (no reveal flag, or no reveal right on the folder).
  final VoidCallback? onReveal;

  /// Null hides the button (no item history on this server).
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final publicKey = entry.meta?['publicKey'] as String?;
    final isKey = entry.meta?['kind'] == IdentityKind.privateKey.name;
    final colors = UfColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            spacing: 14,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.field,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Icon(
                  isKey ? UfIcons.key : UfIcons.lock,
                  size: 18,
                  color: colors.accent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (publicKey == null)
                      Text(
                        isKey ? l.keyKindPrivateKey : l.keyKindPassword,
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      )
                    else
                      Text(
                        publicKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle.copyWith(
                          color: colors.muted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (publicKey != null)
                IconButton(
                  key: Key('identity-copy-${entry.id}'),
                  tooltip: l.keyCopyPublic,
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: publicKey));
                    messenger.showSnackBar(
                      SnackBar(content: Text(l.keyCopied)),
                    );
                  },
                  icon: const Icon(UfIcons.copy, size: 17),
                ),
              if (onReveal != null)
                IconButton(
                  key: Key('identity-reveal-${entry.id}'),
                  tooltip: l.identityReveal,
                  onPressed: onReveal,
                  icon: const Icon(UfIcons.eye, size: 17),
                ),
              if (onHistory != null)
                IconButton(
                  key: Key('identity-history-${entry.id}'),
                  tooltip: l.itemHistory,
                  onPressed: onHistory,
                  icon: const Icon(UfIcons.clockCounterClockwise, size: 17),
                ),
              IconButton(
                key: Key('identity-rename-${entry.id}'),
                tooltip: l.keyRename,
                onPressed: readOnly ? null : onRename,
                icon: const Icon(UfIcons.pencil, size: 17),
              ),
              IconButton(
                key: Key('identity-delete-${entry.id}'),
                tooltip: l.keyDelete,
                onPressed: readOnly ? null : onDelete,
                icon: const Icon(UfIcons.trash, size: 17),
              ),
            ],
          ),
        ),
      ),
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
    final copy = MaterialLocalizations.of(context).copyButtonLabel;
    final s = widget.secret;
    Widget field(String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectionArea(
            child: Text(value, style: monoStyle.copyWith(fontSize: 13)),
          ),
        ),
        IconButton(
          tooltip: copy,
          onPressed: () => _copy(value),
          icon: const Icon(UfIcons.copy, size: 17),
        ),
      ],
    );
    return UfDialog(
      title: l.identityRevealTitle(widget.name),
      actions: [CancelButton(onPressed: () => Navigator.of(context).pop())],
      children: [
        if (s.password case final password?) field(password),
        if (s.passphrase case final passphrase?) field(passphrase),
        if (s.privateKeyPem case final pem?) field(pem),
      ],
    );
  }
}
