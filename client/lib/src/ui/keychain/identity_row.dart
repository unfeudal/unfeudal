// SPDX-License-Identifier: Apache-2.0
part of 'keychain_screen.dart';

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

// The password, or the private key and its passphrase; a copy is wiped from the clipboard after a minute.
class _RevealDialog extends StatefulWidget {
  const _RevealDialog({required this.name, required this.secret});

  final String name;
  final IdentitySecret secret;

  @override
  State<_RevealDialog> createState() => _RevealDialogState();
}

class _RevealDialogState extends State<_RevealDialog> {
  final _clipboard = SecretClipboard();

  @override
  void dispose() {
    _clipboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final s = widget.secret;
    Widget field(String value) =>
        UfReadOnlyField(value: value, onCopy: () => _clipboard.copy(value));
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
