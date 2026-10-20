// SPDX-License-Identifier: Apache-2.0
part of 'keychain_screen.dart';

class _KeychainList extends StatelessWidget {
  const _KeychainList({
    required this.orgFolders,
    required this.folderId,
    required this.onFolderChanged,
    required this.vaultName,
    required this.rows,
    required this.linked,
  });

  final List<VaultEntry> orgFolders;
  final String? folderId;
  final ValueChanged<String?> onFolderChanged;
  final String vaultName;
  final List<Widget> rows;
  final List<VaultEntry> linked;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final caption = Theme.of(context).textTheme.labelSmall!
        .copyWith(color: colors.muted);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        if (orgFolders.isNotEmpty)
          _PlacePicker(
            orgFolders: orgFolders,
            folderId: folderId,
            onChanged: onFolderChanged,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 4),
          child: Text(
            l.keychainOf(
              orgFolders.where((f) => f.id == folderId).firstOrNull?.name ??
                  vaultName,
            ),
            style: caption,
          ),
        ),
        if (rows.isEmpty)
          Text(
            l.keychainEmpty,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: colors.muted),
          ),
        ...rows,
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
    );
  }
}
