// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../design/icons.dart';
import '../design/tokens.dart';

/// A section screen in place of the sessions: back arrow, Alegreya title, an optional subtitle and actions, then
/// the content. Back and Escape call [onBack], or pop the route when the screen was pushed on its own.
class ManageFrame extends StatelessWidget {
  const ManageFrame({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;

  /// The vault or account the section belongs to.
  final String? subtitle;

  /// Buttons right of the title, primary first.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    void back() =>
        onBack != null ? onBack!() : Navigator.of(context).maybePop();
    return Material(
      color: colors.bg,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    IconButton(
                      key: const Key('manage-back'),
                      tooltip: AppLocalizations.of(context).manageBack,
                      onPressed: back,
                      icon: const Icon(UfIcons.caretLeft, size: 18),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.displaySmall),
                          if (subtitle case final subtitle?)
                            Text(
                              subtitle,
                              style: text.bodySmall!.copyWith(
                                color: colors.muted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
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
