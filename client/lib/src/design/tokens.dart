// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

part 'theme.dart';

// The named ramps; components never read them, only the roles of UfColors.
abstract final class _Ramp {
  // pierre: green-tinted greys, light (0) to dark (990)
  static const p0 = Color(0xFFFFFFFF);
  static const p25 = Color(0xFFF6F8F7);
  static const p50 = Color(0xFFEDF0EE);
  static const p100 = Color(0xFFE3E9E5);
  static const p150 = Color(0xFFD8E0DB);
  static const p200 = Color(0xFFCCD6D0);
  static const p300 = Color(0xFF94A39C);
  static const p400 = Color(0xFF7B8A83);
  static const p500 = Color(0xFF6E8077);
  static const p600 = Color(0xFF52605A);
  static const p700 = Color(0xFF3A4740);
  static const p750 = Color(0xFF313C36);
  static const p800 = Color(0xFF28322D);
  static const p850 = Color(0xFF222B27);
  static const p875 = Color(0xFF1E2622);
  static const p900 = Color(0xFF1B221F);
  static const p925 = Color(0xFF161C19);
  static const p950 = Color(0xFF121715);
  static const p975 = Color(0xFF0E1210);
  static const p990 = Color(0xFF18201C);
  // vert-de-gris: the accent
  static const v100 = Color(0xFFD9E8E0);
  static const v200 = Color(0xFFA9CDBA);
  static const v300 = Color(0xFF97BCA9);
  static const v400 = Color(0xFF86AE9A);
  static const v500 = Color(0xFF76A08B);
  static const v600 = Color(0xFF387A64);
  static const v700 = Color(0xFF2F6B57);
  static const v800 = Color(0xFF245544);
  static const v900 = Color(0xFF223229);
  static const v950 = Color(0xFF0F1A15);
  // garance: danger
  static const g100 = Color(0xFFF5DFE3);
  static const g300 = Color(0xFFEC929D);
  static const g400 = Color(0xFFE57A87);
  static const g600 = Color(0xFFC0485C);
  static const g700 = Color(0xFFB03A4E);
  static const g900 = Color(0xFF3A2228);
  static const g950 = Color(0xFF1A0E10);
  // cuivre: warnings
  static const c100 = Color(0xFFF5E6D8);
  static const c400 = Color(0xFFD08A55);
  static const c700 = Color(0xFF9A5523);
  static const c900 = Color(0xFF38291D);
  // lichen: success
  static const l100 = Color(0xFFE4ECD6);
  static const l400 = Color(0xFFB9C77A);
  static const l700 = Color(0xFF4F6526);
  static const l900 = Color(0xFF283020);
}

/// The colour roles; each component reads these, never a hex value.
class UfColors extends ThemeExtension<UfColors> {
  const UfColors({
    required this.bg,
    required this.side,
    required this.panel,
    required this.panelHover,
    required this.field,
    required this.fieldHover,
    required this.fieldPress,
    required this.term,
    required this.line,
    required this.edge,
    required this.text,
    required this.muted,
    required this.disabledBg,
    required this.disabledFg,
    required this.neutral,
    required this.neutralHover,
    required this.neutralPress,
    required this.accent,
    required this.accentHover,
    required this.accentPress,
    required this.accentFg,
    required this.accentText,
    required this.select,
    required this.focus,
    required this.danger,
    required this.dangerHover,
    required this.onDanger,
    required this.dangerSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.scrim,
  });

  /// Grounds: main area, sidebar and bars, floating surfaces, hovered rows, inside inputs, terminal.
  final Color bg, side, panel, panelHover, field, term;

  /// Hovered and pressed choice surfaces: a choice card, a pressed radio.
  final Color fieldHover, fieldPress;

  /// Separators and floating edges; the edge of inputs, boxes and radios.
  final Color line, edge;
  final Color text, muted, disabledBg, disabledFg;

  /// Secondary buttons, segmented tracks and chips.
  final Color neutral, neutralHover, neutralPress;
  final Color accent, accentHover, accentPress, accentFg;

  /// Selected rows and chosen options: [accentText] on [select].
  final Color accentText, select, focus;
  final Color danger, dangerHover, onDanger, dangerSoft;
  final Color ok, okSoft, warn, warnSoft, scrim;

  static const light = UfColors(
    bg: _Ramp.p50,
    side: _Ramp.p25,
    panel: _Ramp.p0,
    panelHover: _Ramp.p50,
    field: _Ramp.p0,
    fieldHover: _Ramp.p25,
    fieldPress: _Ramp.p100,
    term: _Ramp.p0,
    line: _Ramp.p150,
    edge: _Ramp.p400,
    text: _Ramp.p990,
    muted: _Ramp.p600,
    disabledBg: _Ramp.p50,
    disabledFg: _Ramp.p300,
    neutral: _Ramp.p100,
    neutralHover: _Ramp.p150,
    neutralPress: _Ramp.p200,
    accent: _Ramp.v700,
    accentHover: _Ramp.v600,
    accentPress: _Ramp.v800,
    accentFg: _Ramp.p0,
    accentText: _Ramp.v800,
    select: _Ramp.v100,
    focus: _Ramp.v700,
    danger: _Ramp.g700,
    dangerHover: _Ramp.g600,
    onDanger: _Ramp.p0,
    dangerSoft: _Ramp.g100,
    ok: _Ramp.l700,
    okSoft: _Ramp.l100,
    warn: _Ramp.c700,
    warnSoft: _Ramp.c100,
    scrim: Color(0x5918201C),
  );

  static const dark = UfColors(
    bg: _Ramp.p950,
    side: _Ramp.p925,
    panel: _Ramp.p875,
    panelHover: _Ramp.p800,
    field: _Ramp.p900,
    fieldHover: _Ramp.p850,
    fieldPress: _Ramp.p800,
    term: _Ramp.p975,
    line: _Ramp.p800,
    edge: _Ramp.p500,
    text: _Ramp.p100,
    muted: _Ramp.p300,
    disabledBg: _Ramp.p900,
    disabledFg: _Ramp.p600,
    neutral: _Ramp.p800,
    neutralHover: _Ramp.p750,
    neutralPress: _Ramp.p700,
    accent: _Ramp.v400,
    accentHover: _Ramp.v300,
    accentPress: _Ramp.v500,
    accentFg: _Ramp.v950,
    accentText: _Ramp.v200,
    select: _Ramp.v900,
    focus: _Ramp.v200,
    danger: _Ramp.g400,
    dangerHover: _Ramp.g300,
    onDanger: _Ramp.g950,
    dangerSoft: _Ramp.g900,
    ok: _Ramp.l400,
    okSoft: _Ramp.l900,
    warn: _Ramp.c400,
    warnSoft: _Ramp.c900,
    scrim: Color(0x99050807),
  );

  static UfColors of(BuildContext context) =>
      Theme.of(context).extension<UfColors>()!;

  bool get isDark => identical(this, dark) || bg == dark.bg;

  List<Color> get _all => [
    bg, side, panel, panelHover, field, term, line, edge, text, muted, //
    disabledBg, disabledFg, neutral, neutralHover, neutralPress, accent,
    accentHover, accentPress, accentFg, accentText, select, focus, danger,
    dangerHover, onDanger, dangerSoft, ok, okSoft, warn, warnSoft, scrim,
    fieldHover, fieldPress,
  ];

  static UfColors _fromList(List<Color> c) => UfColors(
    bg: c[0],
    side: c[1],
    panel: c[2],
    panelHover: c[3],
    field: c[4],
    term: c[5],
    line: c[6],
    edge: c[7],
    text: c[8],
    muted: c[9],
    disabledBg: c[10],
    disabledFg: c[11],
    neutral: c[12],
    neutralHover: c[13],
    neutralPress: c[14],
    accent: c[15],
    accentHover: c[16],
    accentPress: c[17],
    accentFg: c[18],
    accentText: c[19],
    select: c[20],
    focus: c[21],
    danger: c[22],
    dangerHover: c[23],
    onDanger: c[24],
    dangerSoft: c[25],
    ok: c[26],
    okSoft: c[27],
    warn: c[28],
    warnSoft: c[29],
    scrim: c[30],
    fieldHover: c[31],
    fieldPress: c[32],
  );

  // ThemeExtension asks for it; the two palettes are fixed, so there is nothing to override.
  @override
  UfColors copyWith() => this;

  @override
  UfColors lerp(UfColors? other, double t) {
    if (other == null) return this;
    final a = _all, b = other._all;
    return _fromList([
      for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
    ]);
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

/// Elevation 1 (seated), 2 (floating: menus, notifications) and 3 (dialogs): a `line` edge, then a shadow from 2 up.
abstract final class UfElevation {
  static List<BoxShadow> floating(UfColors c) => [
    BoxShadow(color: c.line, spreadRadius: 1),
    BoxShadow(
      color: Color(c.isDark ? 0x73000000 : 0x1A18201C),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  /// The outer ring of keyboard focus: a 2 px gap in `bg`, then 2 px of `focus` (painted in list order).
  static List<BoxShadow> focusRing(UfColors c) => [
    BoxShadow(color: c.focus, spreadRadius: 4),
    BoxShadow(color: c.bg, spreadRadius: 2),
  ];

  static List<BoxShadow> dialog(UfColors c) => [
    BoxShadow(color: c.line, spreadRadius: 1),
    BoxShadow(
      color: Color(c.isDark ? 0x80000000 : 0x2918201C),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];
}

/// Radii: 4 for keys and badges; 6 for controls, rows and tooltips; 8 for menus, notifications and cards;
/// 10 for dialogs.
abstract final class UfRadius {
  static const key = BorderRadius.all(Radius.circular(4));
  static const control = BorderRadius.all(Radius.circular(6));
  static const card = BorderRadius.all(Radius.circular(8));
  static const dialog = BorderRadius.all(Radius.circular(10));
}

/// Terminal, fingerprints, commands and shortcuts only.
const monoStyle = TextStyle(fontFamily: 'JetBrainsMono');

/// The text of a mono input: keys, fingerprints, commands.
final monoField = monoStyle.copyWith(fontSize: 12);

/// What a field shows when it has no value.
const noValue = '\u2014';

const _ui = 'HankenGrotesk';
const _titles = 'Alegreya';
const _tabular = [FontFeature.tabularFigures()];

/// Control heights: 28 in toolbars and rows, 32 in forms and dialogs, 40 for the single action of an access screen.
abstract final class UfHeight {
  static const small = 28.0, medium = 32.0, large = 40.0;
}
