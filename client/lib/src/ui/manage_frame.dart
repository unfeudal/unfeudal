// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../design/icons.dart';
import '../design/tokens.dart';

/// Keychain, devices and settings: a back arrow and a title over the content, next to the rail.
/// Back and Escape call [onBack], or pop the route when the screen was pushed on its own.
class ManageFrame extends StatelessWidget {
  const ManageFrame({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    void back() =>
        onBack != null ? onBack!() : Navigator.of(context).maybePop();
    // `side`, like the tree it replaces: fields stay visible in the light theme
    return Material(
      color: colors.side,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 22,
              children: [
                Row(
                  spacing: 14,
                  children: [
                    IconButton(
                      key: const Key('manage-back'),
                      tooltip: AppLocalizations.of(context).manageBack,
                      onPressed: back,
                      icon: const Icon(UfIcons.caretLeft, size: 18),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ),
                  ],
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
