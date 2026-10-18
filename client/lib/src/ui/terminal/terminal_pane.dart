// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../terminal/charte_theme.dart';
import '../../terminal/terminal_session.dart';
import '../describe_error.dart';

/// One terminal, in the theme and font of the settings; a failed session shows why above it.
class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key, required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.error case final error?)
            StatusBanner(
              tone: BannerTone.danger,
              message: describeError(AppLocalizations.of(context), error),
            ),
          Expanded(
            child: TerminalView(
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
          ),
        ],
      ),
    );
  }
}
