// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design/icons.dart';
import '../design/logo.dart';
import '../design/tokens.dart';
import '../loquet/loquet_spot.dart';
import '../window/window_chrome.dart';
import 'shell/shell_chrome.dart';

/// The 38 px bar that replaces the system one. Over the home screen its left cell follows the sidebar (`side`,
/// logo, name, the toggle); with the sidebar hidden it holds the toggle and Loquet. Windows: title on the left,
/// caption buttons. macOS: room for the native traffic lights, centred title.
class UfTitleBar extends StatelessWidget {
  const UfTitleBar({
    super.key,
    required this.chrome,
    required this.shell,
    required this.title,
    required this.background,
  });

  final WindowChrome chrome;
  final ShellChrome shell;

  /// Shown until the home shell sets its own.
  final String title;

  /// The ground of the access screens; the home screen uses `bg`.
  final Color background;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return ListenableBuilder(
      listenable: Listenable.merge([chrome.focused, chrome.maximized, shell]),
      builder: (context, _) {
        final dim = chrome.focused.value ? 1.0 : 0.45;
        final maximized = chrome.maximized.value;
        final home = shell.title != null;
        final sidebar = shell.sidebarWidth;
        final toggle = shell.toggleSidebar;
        // no tooltips: the bar sits above the Navigator, outside any Overlay
        Widget barButton(String key, String label, VoidCallback onPressed) =>
            IconButton(
              key: Key(key),
              onPressed: onPressed,
              style: ButtonStyle(
                foregroundColor: _glyph(colors.muted, colors.text),
                iconColor: _glyph(colors.muted, colors.text),
              ),
              icon: Icon(UfIcons.sidebarSimple, semanticLabel: label),
            );
        // Close: `danger` fill and `onDanger` glyph; the others take `neutral`
        Widget caption(
          String label,
          IconData icon,
          VoidCallback onPressed, {
          Color? hoverFill,
          Color? hoverGlyph,
        }) {
          final rest = colors.muted.withValues(alpha: colors.muted.a * dim);
          final glyph = _glyph(rest, hoverGlyph ?? colors.text);
          return IconButton(
            onPressed: onPressed,
            style: ButtonStyle(
              fixedSize: const WidgetStatePropertyAll(Size(46, 38)),
              minimumSize: const WidgetStatePropertyAll(Size(46, 38)),
              maximumSize: const WidgetStatePropertyAll(Size(46, 38)),
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              iconSize: const WidgetStatePropertyAll(12),
              backgroundColor: WidgetStateProperty<Color>.fromMap({
                WidgetState.hovered: hoverFill ?? colors.neutral,
                WidgetState.any: Colors.transparent,
              }),
              foregroundColor: glyph,
              iconColor: glyph,
            ),
            icon: Icon(icon, semanticLabel: label),
          );
        }

        final Widget left;
        if (sidebar != null) {
          left = Container(
            width: sidebar,
            padding: EdgeInsets.only(left: mac ? 78 : 12, right: 6),
            decoration: BoxDecoration(
              color: colors.side,
              border: Border(right: BorderSide(color: colors.line)),
            ),
            child: Opacity(
              opacity: dim,
              child: Row(
                spacing: 8,
                children: [
                  UfLogo(size: 16, color: colors.accent),
                  Text(
                    l.appName.toLowerCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const Spacer(),
                  if (toggle != null)
                    barButton('tree-hide', l.treeHide, toggle),
                ],
              ),
            ),
          );
        } else if (home) {
          left = Padding(
            padding: EdgeInsets.only(left: mac ? 78 : 12, right: 4),
            child: Opacity(
              opacity: dim,
              child: Row(
                spacing: 8,
                children: [
                  if (toggle != null)
                    barButton('tree-show', l.treeShow, toggle),
                  const LoquetSpot(placement: LoquetPlacement.titleBar),
                ],
              ),
            ),
          );
        } else {
          left = mac
              ? const SizedBox(width: 78)
              : SizedBox(
                  width: 44,
                  child: Opacity(
                    opacity: dim,
                    child: Center(
                      child: UfLogo(size: 16, color: colors.accent),
                    ),
                  ),
                );
        }
        // a Material: the bar sits above the Navigator, where text has no default style
        return Material(
          color: home ? colors.bg : background,
          child: Container(
            height: 38,
            decoration: home
                ? BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.line)),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                Expanded(
                  child: chrome.dragArea(
                    Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: mac ? Alignment.center : Alignment.centerLeft,
                      child: Opacity(
                        opacity: dim,
                        child: Text(
                          shell.title ?? title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!mac) ...[
                  caption(l.windowMinimize, UfIcons.minus, chrome.minimize),
                  caption(
                    maximized ? l.windowRestore : l.windowMaximize,
                    maximized ? UfIcons.copySimple : UfIcons.square,
                    chrome.toggleMaximize,
                  ),
                  caption(
                    l.windowClose,
                    UfIcons.x,
                    chrome.close,
                    hoverFill: colors.danger,
                    hoverGlyph: colors.onDanger,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// [rest] until hovered, then [hover].
WidgetStateProperty<Color> _glyph(Color rest, Color hover) =>
    WidgetStateProperty<Color>.fromMap({
      WidgetState.hovered: hover,
      WidgetState.any: rest,
    });
