// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';
import 'package:xterm2/xterm.dart';

import '../design/tokens.dart';
import '../settings/settings.dart';

/// Charte: the token hues on `term`, each adjusted until it reads at 4.5:1 on it.
final charteLight = _charte(UfColors.light, background: UfColors.light.term);

final charteDark = _charte(UfColors.dark, background: UfColors.dark.term);

/// Published Solarized Dark palette.
const solarizedDark = TerminalTheme(
  cursor: Color(0xFF93A1A1),
  selection: Color(0xFF073642),
  foreground: Color(0xFF839496),
  background: Color(0xFF002B36),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF002B36),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: Color(0xFFB58900),
  searchHitBackgroundCurrent: Color(0xFFCB4B16),
  searchHitForeground: Color(0xFF002B36),
);

/// Published Dracula palette.
const dracula = TerminalTheme(
  cursor: Color(0xFFF8F8F2),
  selection: Color(0xFF44475A),
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF282A36),
  black: Color(0xFF21222C),
  red: Color(0xFFFF5555),
  green: Color(0xFF50FA7B),
  yellow: Color(0xFFF1FA8C),
  blue: Color(0xFFBD93F9),
  magenta: Color(0xFFFF79C6),
  cyan: Color(0xFF8BE9FD),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF6272A4),
  brightRed: Color(0xFFFF6E6E),
  brightGreen: Color(0xFF69FF94),
  brightYellow: Color(0xFFFFFFA5),
  brightBlue: Color(0xFFD6ACFF),
  brightMagenta: Color(0xFFFF92DF),
  brightCyan: Color(0xFFA4FFFF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFF1FA8C),
  searchHitBackgroundCurrent: Color(0xFFFFB86C),
  searchHitForeground: Color(0xFF282A36),
);

/// Solarized Dark and Dracula ignore the brightness.
TerminalTheme terminalThemeFor(TerminalThemeId id, Brightness brightness) =>
    switch (id) {
      TerminalThemeId.charte =>
        brightness == Brightness.light ? charteLight : charteDark,
      TerminalThemeId.solarizedDark => solarizedDark,
      TerminalThemeId.dracula => dracula,
    };

TerminalTheme _charte(UfColors c, {required Color background}) {
  Color read(Color hue) => _readable(hue, background);
  // magenta and cyan have no token: a plum and a teal between garance, vert-de-gris and lichen
  final magenta = read(Color.lerp(c.danger, c.accent, 0.5)!);
  final cyan = read(Color.lerp(c.ok, c.accent, 0.5)!);
  return TerminalTheme(
    cursor: c.accent,
    selection: c.select,
    foreground: read(c.text),
    background: background,
    black: read(c.muted),
    red: read(c.danger),
    green: read(c.ok),
    yellow: read(c.warn),
    blue: read(c.accent),
    magenta: magenta,
    cyan: cyan,
    white: read(c.text),
    brightBlack: read(c.muted),
    brightRed: read(c.danger),
    brightGreen: read(c.ok),
    brightYellow: read(c.warn),
    brightBlue: read(c.accent),
    brightMagenta: magenta,
    brightCyan: cyan,
    brightWhite: read(c.text),
    searchHitBackground: c.warn,
    searchHitBackgroundCurrent: c.accent,
    searchHitForeground: c.accentFg,
  );
}

// Moves color away from background in lightness until the pair reaches 4.5:1.
Color _readable(Color color, Color background) {
  final darker = background.computeLuminance() > 0.5;
  var hsl = HSLColor.fromColor(color);
  while (_contrast(hsl.toColor(), background) < 4.5 &&
      hsl.lightness > 0 &&
      hsl.lightness < 1) {
    hsl = hsl.withLightness(
      (hsl.lightness + (darker ? -0.02 : 0.02)).clamp(0.0, 1.0),
    );
  }
  return hsl.toColor();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}
