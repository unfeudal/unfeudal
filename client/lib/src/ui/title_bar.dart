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
        final home = shell.title != null;
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
                _LeftCell(shell: shell, mac: mac, dim: dim),
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
                if (!mac) ..._captionButtons(l, colors, dim),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _captionButtons(
    AppLocalizations l,
    UfColors colors,
    double dim,
  ) {
    final maximized = chrome.maximized.value;
    return [
      _CaptionButton(
        label: l.windowMinimize,
        icon: UfIcons.minus,
        onPressed: chrome.minimize,
        dim: dim,
      ),
      _CaptionButton(
        label: maximized ? l.windowRestore : l.windowMaximize,
        icon: maximized ? UfIcons.copySimple : UfIcons.square,
        onPressed: chrome.toggleMaximize,
        dim: dim,
      ),
      _CaptionButton(
        label: l.windowClose,
        icon: UfIcons.x,
        onPressed: chrome.close,
        dim: dim,
        hoverFill: colors.danger,
        hoverGlyph: colors.onDanger,
      ),
    ];
  }
}

// No tooltips: the bar sits above the Navigator, outside any Overlay.
Widget _sidebarToggle(String key, String label, VoidCallback onPressed) =>
    IconButton(
      key: Key(key),
      onPressed: onPressed,
      icon: Icon(UfIcons.sidebarSimple, semanticLabel: label),
    );

// The cell left of the title: the sidebar's own (logo, name, hide), the show toggle and Loquet over the home
// screen with the sidebar hidden, else the logo or room for the traffic lights.
class _LeftCell extends StatelessWidget {
  const _LeftCell({required this.shell, required this.mac, required this.dim});

  final ShellChrome shell;
  final bool mac;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final sidebar = shell.sidebarWidth;
    final toggle = shell.toggleSidebar;
    if (sidebar != null) {
      return Container(
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
                _sidebarToggle('tree-hide', l.treeHide, toggle),
            ],
          ),
        ),
      );
    }
    if (shell.title != null) {
      return Padding(
        padding: EdgeInsets.only(left: mac ? 78 : 12, right: 4),
        child: Opacity(
          opacity: dim,
          child: Row(
            spacing: 8,
            children: [
              if (toggle != null)
                _sidebarToggle('tree-show', l.treeShow, toggle),
              const LoquetSpot(placement: LoquetPlacement.titleBar),
            ],
          ),
        ),
      );
    }
    if (mac) return const SizedBox(width: 78);
    return SizedBox(
      width: 44,
      child: Opacity(
        opacity: dim,
        child: Center(child: UfLogo(size: 16, color: colors.accent)),
      ),
    );
  }
}

// Close: `danger` fill and `onDanger` glyph; the others take `neutral`.
class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.dim,
    this.hoverFill,
    this.hoverGlyph,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double dim;
  final Color? hoverFill;
  final Color? hoverGlyph;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
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
}

WidgetStateProperty<Color> _glyph(Color rest, Color hover) =>
    WidgetStateProperty<Color>.fromMap({
      WidgetState.hovered: hover,
      WidgetState.any: rest,
    });
