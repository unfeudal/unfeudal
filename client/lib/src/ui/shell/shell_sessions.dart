// SPDX-License-Identifier: Apache-2.0
part of 'home_shell.dart';

StatusBanner _rejectedBanner(
  AppLocalizations l,
  AppState state,
  OutboxEntry entry,
) {
  final sync = state.sync!;
  final id = entry.item.id;
  return StatusBanner(
    tone: BannerTone.danger,
    message: l.bannerRejected(
      state.vault?.entry(id)?.name ?? entry.item.type,
      describeError(l, ApiException(entry.lastError ?? 'internal', 0)),
    ),
    action: (l.rejectedRetry, () => unawaited(sync.retry(id))),
    secondAction: (l.rejectedKeep, () => unawaited(sync.keepPersonalCopy(id))),
    onDismiss: () => unawaited(sync.discard(id)),
    dismissTooltip: l.rejectedDiscard,
    actionKey: Key('unsynced-retry-$id'),
    secondActionKey: Key('unsynced-keep-$id'),
    dismissKey: Key('unsynced-discard-$id'),
  );
}

String _readOnlyReason(AppLocalizations l, SyncEngine sync) =>
    switch (sync.compat?.reason) {
      'no-common-api' => l.readOnlyNoCommonApi,
      'client-too-old' => l.readOnlyClientTooOld,
      _ => l.bannerRestoreRefused,
    };

// The status banners over the terminal tabs, with the open inspector docked on their right.
class _Sessions extends StatelessWidget {
  const _Sessions({
    required this.banners,
    required this.terminalFocus,
    required this.onNewTab,
    required this.onEditHost,
    required this.editor,
  });

  final List<Widget> banners;
  final FocusNode terminalFocus;
  final VoidCallback onNewTab;
  final ValueChanged<String> onEditHost;
  final Widget? editor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ...banners,
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Focus(
                focusNode: terminalFocus,
                child: TerminalTabs(onNewTab: onNewTab, onEditHost: onEditHost),
              ),
            ),
            if (editor case final editor?)
              GrowIn(key: ObjectKey(editor), child: editor),
          ],
        ),
      ),
    ],
  );
}
