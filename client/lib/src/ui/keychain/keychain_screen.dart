// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/empty_state.dart';
import '../../design/dialog.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../keys/key_tools.dart';
import '../../vault/vault.dart';
import '../form_dialog.dart';
import '../manage_frame.dart';

/// SSH keys and passwords of the vault: generate, import, add a password, copy a public key, rename, trash.
class KeychainScreen extends StatelessWidget {
  const KeychainScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final vault = state.vault!;
    final readOnly = state.sync?.readOnly ?? true;
    final identities =
        vault
            .ofKind(ItemKind.identity)
            .where((e) => e.state == EntryState.ok)
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
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
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
                        (v) => _generate(vault, v),
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
                        (v) => _import(vault, v),
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
                        (v) => _password(vault, v),
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
                            (v) => vault.updateIdentity(
                              e.id,
                              IdentityMeta.fromJson({
                                ...?e.meta,
                                'name': v['identity-name']!.trim(),
                              }),
                            ),
                            initial: {'identity-name': e.name ?? ''},
                          ),
                          onDelete: () => _confirmTrash(context, vault, e),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Future<void> _generate(Vault vault, Map<String, String> v) async {
    final passphrase = v['gen-passphrase']!.isEmpty
        ? null
        : v['gen-passphrase'];
    final name = v['gen-name']!.trim();
    final key = v['gen-type-rsa'] == 'true'
        ? await generateRsa4096(comment: name, passphrase: passphrase)
        : await generateEd25519(comment: name, passphrase: passphrase);
    await _savePrivateKey(
      vault,
      name,
      key.privateKeyPem,
      passphrase,
      key.publicKey,
    );
  }

  /// The key is read (and its passphrase checked) before anything is stored; the original text is kept.
  static Future<void> _import(Vault vault, Map<String, String> v) async {
    final passphrase = v['import-passphrase']!.isEmpty
        ? null
        : v['import-passphrase'];
    final pem = v['import-pem']!.trim();
    final publicKey = publicKeyOf(pem, passphrase: passphrase);
    await _savePrivateKey(
      vault,
      v['import-name']!.trim(),
      pem,
      passphrase,
      publicKey,
    );
  }

  static Future<void> _savePrivateKey(
    Vault vault,
    String name,
    String pem,
    String? passphrase,
    String publicKey,
  ) => vault.upsertItem(
    type: 'identity',
    meta: IdentityMeta(
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

  static Future<void> _password(Vault vault, Map<String, String> v) =>
      vault.upsertItem(
        type: 'identity',
        meta: IdentityMeta(
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
    Vault vault,
    VaultEntry e,
  ) async {
    final l = AppLocalizations.of(context);
    final yes = await confirmDanger(
      context,
      question: l.keyDeleteConfirm(e.name ?? ''),
      action: l.keyDelete,
    );
    if (yes) await vault.trashItem(e.id);
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.entry,
    required this.readOnly,
    required this.onRename,
    required this.onDelete,
  });

  final VaultEntry entry;
  final bool readOnly;
  final VoidCallback onRename;
  final VoidCallback onDelete;

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
