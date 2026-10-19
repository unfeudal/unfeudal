// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/logo.dart';
import '../../design/tokens.dart';
import '../../terminal/charte_theme.dart';
import '../../terminal/terminal_session.dart';
import '../describe_error.dart';

class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key, required this.session, this.onEditHost});

  final TerminalSession session;
  final void Function(String hostId)? onEditHost;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => switch (session.error) {
        final Object error => _ErrorCard(
          session: session,
          error: error,
          onEditHost: onEditHost,
        ),
        null => TerminalView(
          session.terminal,
          autofocus: true,
          theme: terminalThemeFor(
            settings.terminalTheme,
            Theme.of(context).brightness,
          ),
          textStyle: TerminalStyle(
            fontFamily: settings.terminalFont,
            fontSize: settings.terminalFontSize.toDouble(),
          ),
        ),
      },
    );
  }
}

/// A failed session stays in its tab: what happened, then retry or edit. Never the exception text.
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
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
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
              Row(
                spacing: 20,
                children: [
                  // Loquet's place
                  UfLogo(size: 64, color: colors.muted),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Text(
                          l.tabErrorTitle(session.title),
                          style: text.titleLarge,
                        ),
                        Text(
                          describeError(l, error),
                          key: const Key('tab-error'),
                          style: text.bodyLarge!.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('tab-retry'),
                    onPressed: () async {
                      await state.closeTab(session);
                      await state.connect(session.hostId);
                    },
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
