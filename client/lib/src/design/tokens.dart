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
    required this.onDanger,
    required this.term,
    required this.scrim,
    required this.dangerSoft,
    required this.dangerText,
    required this.warnSoft,
    required this.warnText,
    required this.okSoft,
    required this.infoSoft,
  });

  final Color bg, rail, side, panel, field, select, text, muted;
  final Color accent, accentBg, accentFg, ok, warn, danger, onDanger;

  /// Terminal background, dialog scrim, and the soft fills of banners and notices.
  final Color term,
      scrim,
      dangerSoft,
      dangerText,
      warnSoft,
      warnText,
      okSoft,
      infoSoft;

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
    onDanger: Color(0xFFFFFFFF),
    term: Color(0xFFF8FAF9),
    scrim: Color(0x73252B31),
    dangerSoft: Color(0xFFF6E3E0),
    dangerText: Color(0xFFA23B32),
    warnSoft: Color(0xFFF3ECD9),
    warnText: Color(0xFF7A5D17),
    okSoft: Color(0xFFE3EADB),
    infoSoft: Color(0xFFDCE6F0),
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
    onDanger: Color(0xFF171B1F),
    term: Color(0xFF1F2429),
    scrim: Color(0x9E0A0C0E),
    dangerSoft: Color(0xFF3A2624),
    dangerText: Color(0xFFE07A70),
    warnSoft: Color(0xFF2E2A1E),
    warnText: Color(0xFFC9A54E),
    okSoft: Color(0xFF26301F),
    infoSoft: Color(0xFF1F2B38),
  );

  static UfColors of(BuildContext context) =>
      Theme.of(context).extension<UfColors>()!;

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
    onDanger,
    term,
    scrim,
    dangerSoft,
    dangerText,
    warnSoft,
    warnText,
    okSoft,
    infoSoft,
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
    Color? onDanger,
    Color? term,
    Color? scrim,
    Color? dangerSoft,
    Color? dangerText,
    Color? warnSoft,
    Color? warnText,
    Color? okSoft,
    Color? infoSoft,
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
    onDanger: onDanger ?? this.onDanger,
    term: term ?? this.term,
    scrim: scrim ?? this.scrim,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    dangerText: dangerText ?? this.dangerText,
    warnSoft: warnSoft ?? this.warnSoft,
    warnText: warnText ?? this.warnText,
    okSoft: okSoft ?? this.okSoft,
    infoSoft: infoSoft ?? this.infoSoft,
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
      onDanger: mix(onDanger, other.onDanger),
      term: mix(term, other.term),
      scrim: mix(scrim, other.scrim),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      dangerText: mix(dangerText, other.dangerText),
      warnSoft: mix(warnSoft, other.warnSoft),
      warnText: mix(warnText, other.warnText),
      okSoft: mix(okSoft, other.okSoft),
      infoSoft: mix(infoSoft, other.infoSoft),
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

/// Terminal and fingerprints only.
const monoStyle = TextStyle(fontFamily: 'JetBrainsMono');

const _ui = 'HankenGrotesk';
const _titles = 'Alegreya';
const _tabular = [FontFeature.tabularFigures()];
const _controlRadius = BorderRadius.all(Radius.circular(8));

ThemeData ufTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? UfColors.light : UfColors.dark;
  TextStyle title(double size) => TextStyle(
    fontFamily: _titles,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1.1,
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
    displaySmall: title(34),
    headlineLarge: title(40),
    headlineMedium: title(26),
    headlineSmall: title(21),
    titleLarge: title(22),
    titleMedium: ui(15, FontWeight.w600),
    titleSmall: ui(13, FontWeight.w600),
    bodyLarge: ui(15),
    bodyMedium: ui(14),
    bodySmall: ui(13),
    labelLarge: ui(14, FontWeight.w600),
    labelMedium: ui(13, FontWeight.w600),
    labelSmall: ui(12, FontWeight.w600),
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  const buttonShape = RoundedRectangleBorder(borderRadius: _controlRadius);
  // fromMap compares by value: a closure would make every ufTheme() unequal and animate theme changes
  final selectedFill = WidgetStateProperty<Color>.fromMap({
    WidgetState.selected: c.accentBg,
    WidgetState.any: c.field,
  });
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
    visualDensity: VisualDensity.standard,
    hoverColor: c.accent.withValues(alpha: 0.10),
    focusColor: c.accent.withValues(alpha: 0.14),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accentBg,
        foregroundColor: c.accentFg,
        disabledBackgroundColor: c.accentBg.withValues(alpha: 0.5),
        disabledForegroundColor: c.accentFg.withValues(alpha: 0.8),
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    // secondary actions: a flat `field` fill, no outline (fills over borders)
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.field,
        foregroundColor: c.text,
        side: BorderSide.none,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.bodyMedium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.muted, shape: buttonShape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      hintStyle: text.bodyMedium!.copyWith(color: c.muted),
      helperStyle: text.labelSmall!.copyWith(
        color: c.muted,
        fontWeight: FontWeight.w400,
      ),
      errorStyle: text.labelSmall!.copyWith(color: c.danger),
      border: const OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide.none,
      ),
      // fills over borders, except the focus ring: the accent marks focus
      focusedBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _controlRadius,
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      color: selectedFill,
      labelStyle: text.bodyMedium,
      secondaryLabelStyle: text.labelLarge!.copyWith(color: c.accentFg),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: selectedFill,
      checkColor: WidgetStatePropertyAll(c.accentFg),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      trackColor: selectedFill,
      thumbColor: WidgetStateProperty<Color>.fromMap({
        WidgetState.selected: c.accentFg,
        WidgetState.any: c.muted,
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.text, borderRadius: _controlRadius),
      textStyle: text.bodySmall!.copyWith(color: c.bg),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: text.bodyMedium!.copyWith(color: c.bg),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: _controlRadius),
    ),
    cardTheme: const CardThemeData(elevation: 0),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
