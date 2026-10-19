// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design/icons.dart';
import '../design/logo.dart';
import '../design/tokens.dart';
import '../window/window_chrome.dart';

/// The 38 px bar that replaces the system one. Windows: logo over the rail, title, caption buttons.
/// macOS: room for the native traffic lights, centred title.
class UfTitleBar extends StatelessWidget {
  const UfTitleBar({
    super.key,
    required this.chrome,
    required this.title,
    required this.background,
  });

  final WindowChrome chrome;
  final String title;

  /// `rail` over the vault, `bg` over the access screens.
  final Color background;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return ListenableBuilder(
      listenable: Listenable.merge([chrome.focused, chrome.maximized]),
      builder: (context, _) {
        final dim = chrome.focused.value ? 1.0 : 0.45;
        final maximized = chrome.maximized.value;
        // a Material: the bar sits above the Navigator, where text has no default style
        return Material(
          color: background,
          child: SizedBox(
            height: 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mac)
                  const SizedBox(width: 78)
                else
                  SizedBox(
                    width: 60,
                    child: Opacity(
                      opacity: dim,
                      child: Center(
                        child: UfLogo(size: 18, color: colors.accent),
                      ),
                    ),
                  ),
                Expanded(
                  child: chrome.dragArea(
                    Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: mac ? Alignment.center : Alignment.centerLeft,
                      child: Opacity(
                        opacity: dim,
                        child: Text(
                          title,
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

  /// Close: `danger` fill and `onDanger` glyph; the others take a light accent tint.
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
        : widget.hoverFill ?? colors.accent.withValues(alpha: 0.16);
    final glyph = _hover ? widget.hoverGlyph ?? colors.text : colors.text;
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
              child: Icon(widget.icon, size: 13, color: glyph),
            ),
          ),
        ),
      ),
    );
  }
}
