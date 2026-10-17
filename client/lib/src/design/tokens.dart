// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

class UfColors extends ThemeExtension<UfColors> {
  const UfColors({
    required this.bg,
    required this.rail,
    required this.side,
    required this.panel,
    required this.field,
    required this.select,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentBg,
    required this.accentFg,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  final Color bg, rail, side, panel, field, select, text, muted;
  final Color accent, accentBg, accentFg, ok, warn, danger;

  static const light = UfColors(
    bg: Color(0xFFE7ECEA),
    rail: Color(0xFFDCE3E0),
    side: Color(0xFFEEF2F0),
    panel: Color(0xFFFFFFFF),
    field: Color(0xFFE4E9E7),
    select: Color(0xFFD3DEEA),
    text: Color(0xFF252B31),
    muted: Color(0xFF5A646D),
    accent: Color(0xFF23466E),
    accentBg: Color(0xFF23466E),
    accentFg: Color(0xFFF4F7FA),
    ok: Color(0xFF56664A),
    warn: Color(0xFF8A6A1F),
    danger: Color(0xFFA23B32),
  );

  static const dark = UfColors(
    bg: Color(0xFF171B1F),
    rail: Color(0xFF121518),
    side: Color(0xFF1B2025),
    panel: Color(0xFF22282E),
    field: Color(0xFF2A3138),
    select: Color(0xFF26374B),
    text: Color(0xFFE1E7E4),
    muted: Color(0xFF97A29D),
    accent: Color(0xFF8EB0D8),
    accentBg: Color(0xFF2F5A8A),
    accentFg: Color(0xFFF2F6FA),
    ok: Color(0xFF9DB089),
    warn: Color(0xFFC9A54E),
    danger: Color(0xFFD9645A),
  );

  List<Color> get _all => [
    bg,
    rail,
    side,
    panel,
    field,
    select,
    text,
    muted,
    accent,
    accentBg,
    accentFg,
    ok,
    warn,
    danger,
  ];

  @override
  UfColors copyWith({
    Color? bg,
    Color? rail,
    Color? side,
    Color? panel,
    Color? field,
    Color? select,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentBg,
    Color? accentFg,
    Color? ok,
    Color? warn,
    Color? danger,
  }) => UfColors(
    bg: bg ?? this.bg,
    rail: rail ?? this.rail,
    side: side ?? this.side,
    panel: panel ?? this.panel,
    field: field ?? this.field,
    select: select ?? this.select,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    accentBg: accentBg ?? this.accentBg,
    accentFg: accentFg ?? this.accentFg,
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
    danger: danger ?? this.danger,
  );

  @override
  UfColors lerp(UfColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return UfColors(
      bg: mix(bg, other.bg),
      rail: mix(rail, other.rail),
      side: mix(side, other.side),
      panel: mix(panel, other.panel),
      field: mix(field, other.field),
      select: mix(select, other.select),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      accentBg: mix(accentBg, other.accentBg),
      accentFg: mix(accentFg, other.accentFg),
      ok: mix(ok, other.ok),
      warn: mix(warn, other.warn),
      danger: mix(danger, other.danger),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! UfColors) return false;
    final a = _all, b = other._all;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_all);
}

/// Terminal and fingerprints only (RFC 0009 typography).
const monoStyle = TextStyle(fontFamily: 'JetBrainsMono');

const _ui = 'HankenGrotesk';
const _titles = 'Alegreya';
const _tabular = [FontFeature.tabularFigures()];
final _controlShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(8),
);

ThemeData ufTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? UfColors.light : UfColors.dark;
  TextStyle title(double size) => TextStyle(
    fontFamily: _titles,
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: c.text,
  );
  TextStyle ui(double size, [FontWeight weight = FontWeight.w400]) => TextStyle(
    fontFamily: _ui,
    fontSize: size,
    fontWeight: weight,
    fontFeatures: _tabular,
    color: c.text,
  );
  final text = TextTheme(
    headlineLarge: title(40),
    headlineMedium: title(26),
    headlineSmall: title(21),
    titleMedium: ui(15, FontWeight.w600),
    titleSmall: ui(13, FontWeight.w600),
    bodyLarge: ui(15),
    bodyMedium: ui(14),
    bodySmall: ui(13),
    labelLarge: ui(14, FontWeight.w600),
    labelMedium: ui(13, FontWeight.w600),
    labelSmall: ui(12, FontWeight.w600),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _ui,
    extensions: [c],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accentBg,
      onPrimary: c.accentFg,
      secondary: c.accent,
      onSecondary: c.bg,
      error: c.danger,
      onError: c.bg,
      surface: c.panel,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceTint: Colors.transparent,
    ),
    scaffoldBackgroundColor: c.bg,
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accentBg,
        foregroundColor: c.accentFg,
        shape: _controlShape,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      // fills over borders, except the focus ring: accent marks focus (RFC 0009 tokens)
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
    ),
    cardTheme: const CardThemeData(elevation: 0),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      elevation: 8,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: text.headlineSmall,
    ),
  );
}
