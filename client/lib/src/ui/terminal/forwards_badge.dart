// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/tokens.dart';
import '../../terminal/terminal_session.dart';
import '../describe_error.dart';

/// The active forward count of a tab; its popover starts and stops each forward. Writes nothing to the
/// vault, so it works in read-only mode.
class ForwardsBadge extends StatelessWidget {
  const ForwardsBadge({
    super.key,
    required this.tab,
    required this.configured,
    required this.index,
  });

  final TerminalSession tab;
  final List<PortForward> configured;
  final int index;

  @override
  Widget build(BuildContext context) {
    final forwarder = tab.forwarder;
    if (forwarder == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    return ListenableBuilder(
      listenable: forwarder,
      builder: (context, _) {
        final active = forwarder.active;
        if (configured.isEmpty && active.isEmpty) {
          return const SizedBox.shrink();
        }
        final rows = [
          ...configured,
          for (final h in active.values)
            if (!configured.any((c) => c.localPort == h.forward.localPort))
              h.forward,
        ];
        return MenuAnchor(
          menuChildren: [
            for (final f in rows)
              _ForwardRow(
                l: l,
                state: state,
                tab: tab,
                forward: f,
                running: active.containsKey(f.localPort),
                failure: forwarder.failed[f.localPort],
              ),
          ],
          builder: (context, controller, _) => Tooltip(
            message: l.forwardsActive(active.length),
            child: InkWell(
              key: Key('forwards-badge-$index'),
              borderRadius: UfRadius.key,
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: active.isEmpty ? colors.neutral : colors.accent,
                  borderRadius: UfRadius.key,
                ),
                child: Text(
                  '${active.length}',
                  style: monoStyle.copyWith(
                    fontSize: 11,
                    height: 16 / 11,
                    color: active.isEmpty ? colors.muted : colors.accentFg,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ForwardRow extends StatelessWidget {
  const _ForwardRow({
    required this.l,
    required this.state,
    required this.tab,
    required this.forward,
    required this.running,
    required this.failure,
  });

  final AppLocalizations l;
  final AppState state;
  final TerminalSession tab;
  final PortForward forward;
  final bool running;
  final Object? failure;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final port = forward.localPort;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Text(
                '127.0.0.1:$port → ${forward.remoteHost}:${forward.remotePort}',
                style: monoStyle.copyWith(fontSize: 12, color: colors.text),
              ),
              running
                  ? TextButton(
                      key: Key('forward-stop-$port'),
                      onPressed: () => state.stopForward(tab, port),
                      child: Text(l.forwardStop),
                    )
                  : TextButton(
                      key: Key('forward-start-$port'),
                      onPressed: () async {
                        try {
                          await state.startForward(tab, forward);
                        } on Exception {
                          // shown under the row from forwarder.failed
                        }
                      },
                      child: Text(l.forwardStart),
                    ),
            ],
          ),
          if (failure case final error?)
            Text(
              describeError(l, error),
              style: TextStyle(color: colors.danger, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
