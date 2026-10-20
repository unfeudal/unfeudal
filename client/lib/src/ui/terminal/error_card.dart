// SPDX-License-Identifier: Apache-2.0
part of 'terminal_pane.dart';

// A failed session stays in its tab: what happened, then retry or edit. Never the exception text.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.session,
    required this.error,
    this.onEditHost,
  });

  final TerminalSession session;
  final Object error;
  final void Function(String hostId)? onEditHost;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              _ErrorHeadline(title: session.title, error: error),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('tab-retry'),
                    onPressed: () => state.connections.reconnect(session),
                    child: Text(l.tabRetry),
                  ),
                  if (onEditHost case final edit?)
                    OutlinedButton(
                      key: const Key('tab-edit-host'),
                      onPressed: () => edit(session.hostId),
                      child: Text(l.tabEditHost),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorHeadline extends StatelessWidget {
  const _ErrorHeadline({required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      spacing: 20,
      children: [
        LoquetSpot(
          key: const Key('tab-error-card'),
          placement: LoquetPlacement.empty,
          mood: switch (error) {
            HostKeyRejected(decision: HostKeyDecision.changed) =>
              LoquetMood.alert,
            _ => LoquetMood.sad,
          },
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text(l.tabErrorTitle(title), style: text.titleLarge),
              Text(
                describeError(l, error),
                key: const Key('tab-error'),
                style: text.bodyMedium!.copyWith(
                  color: colors.muted,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
