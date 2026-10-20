// SPDX-License-Identifier: Apache-2.0
part of 'keychain_screen.dart';

class _PlacePicker extends StatelessWidget {
  const _PlacePicker({
    required this.orgFolders,
    required this.folderId,
    required this.onChanged,
  });

  final List<VaultEntry> orgFolders;
  final String? folderId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 320,
        child: UfField(
          label: l.keychainPlace,
          child: UfSelect<String?>(
            key: const Key('keychain-place'),
            value: folderId,
            options: [
              for (final f in orgFolders)
                UfOption(
                  f.id,
                  f.name ?? '',
                  key: Key('keychain-place-${f.id}'),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
