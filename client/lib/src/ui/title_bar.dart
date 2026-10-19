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
                    _BarButton(
                      key: const Key('tree-hide'),
                      label: l.treeHide,
                      icon: UfIcons.sidebarSimple,
                      onPressed: toggle,
                    ),
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
                    _BarButton(
                      key: const Key('tree-show'),
                      label: l.treeShow,
                      icon: UfIcons.sidebarSimple,
                      onPressed: toggle,
                    ),
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
                  _CaptionButton(
                    tooltip: l.windowMinimize,
                    icon: UfIcons.minus,
                    dim: dim,
                    onPressed: chrome.minimize,
                  ),
                  _CaptionButton(
                    tooltip: maximized ? l.windowRestore : l.windowMaximize,
                    icon: maximized ? UfIcons.copySimple : UfIcons.square,
                    dim: dim,
                    onPressed: chrome.toggleMaximize,
                  ),
                  _CaptionButton(
                    tooltip: l.windowClose,
                    icon: UfIcons.x,
                    dim: dim,
                    hoverFill: colors.danger,
                    hoverGlyph: colors.onDanger,
                    onPressed: chrome.close,
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

/// A 28 px icon button for the bar; no Tooltip, the bar sits outside any Overlay.
class _BarButton extends StatefulWidget {
  const _BarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Semantics(
            button: true,
            label: widget.label,
            child: Container(
              width: UfHeight.small,
              height: UfHeight.small,
              decoration: BoxDecoration(
                color: _hover ? colors.neutral : Colors.transparent,
                borderRadius: UfRadius.control,
              ),
              child: Icon(
                widget.icon,
                size: 16,
                color: _hover ? colors.text : colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 46 × 38 px caption button.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.dim,
    required this.onPressed,
    this.hoverFill,
    this.hoverGlyph,
  });

  final String tooltip;
  final IconData icon;
  final double dim;
  final VoidCallback onPressed;

  /// Close: `danger` fill and `onDanger` glyph; the others take `neutral`.
  final Color? hoverFill;
  final Color? hoverGlyph;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final fill = !_hover
        ? Colors.transparent
        : widget.hoverFill ?? colors.neutral;
    final glyph = _hover ? widget.hoverGlyph ?? colors.text : colors.muted;
    // no Tooltip: the bar sits above the Navigator, outside any Overlay
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: Container(
            width: 46,
            color: fill,
            alignment: Alignment.center,
            child: Opacity(
              opacity: _hover ? 1 : widget.dim,
              child: Icon(widget.icon, size: 12, color: glyph),
            ),
          ),
        ),
      ),
    );
  }
}
