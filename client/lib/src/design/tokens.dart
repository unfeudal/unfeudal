// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

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

  // ponytail: no per-role overrides, the two palettes are fixed; add named parameters when a caller needs one
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

ThemeData ufTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? UfColors.light : UfColors.dark;
  TextStyle title(double size, double height) => TextStyle(
    fontFamily: _titles,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: height,
    color: c.text,
  );
  // only 400 and 600 are bundled
  TextStyle ui(double size, [FontWeight weight = FontWeight.w400]) => TextStyle(
    fontFamily: _ui,
    fontSize: size,
    fontWeight: weight,
    height: 1.45,
    fontFeatures: _tabular,
    color: c.text,
  );
  final text = TextTheme(
    displaySmall: title(32, 1.1),
    headlineLarge: title(32, 1.1),
    headlineMedium: title(20, 1.2),
    headlineSmall: title(20, 1.2),
    titleLarge: title(20, 1.2),
    titleMedium: ui(16, FontWeight.w600).copyWith(height: 1.3),
    titleSmall: ui(13, FontWeight.w600),
    bodyLarge: ui(13.5),
    bodyMedium: ui(14),
    bodySmall: ui(12),
    labelLarge: ui(13, FontWeight.w600),
    labelMedium: ui(13, FontWeight.w600),
    labelSmall: ui(12, FontWeight.w600),
  );
  const padding = EdgeInsets.symmetric(horizontal: 14);
  const shape = RoundedRectangleBorder(borderRadius: UfRadius.control);
  const size = Size(0, UfHeight.medium);
  // fromMap compares by value: a closure would make every ufTheme() unequal and animate theme changes
  WidgetStateProperty<Color> fill(Color rest, Color hover, Color press) =>
      WidgetStateProperty<Color>.fromMap({
        WidgetState.disabled: c.disabledBg,
        WidgetState.pressed: press,
        WidgetState.hovered: hover,
        WidgetState.any: rest,
      });
  WidgetStateProperty<Color> ink(Color rest) =>
      WidgetStateProperty<Color>.fromMap({
        WidgetState.disabled: c.disabledFg,
        WidgetState.any: rest,
      });
  // keyboard focus: a 2 px `focus` stroke outside the shape
  final focusRing = WidgetStateBorderSide.fromMap({
    WidgetState.focused: BorderSide(
      color: c.focus,
      width: 2,
      strokeAlign: BorderSide.strokeAlignOutside,
    ),
    WidgetState.any: BorderSide.none,
  });
  const cursor = WidgetStateMouseCursor.fromMap({
    WidgetState.disabled: SystemMouseCursors.forbidden,
    WidgetState.any: SystemMouseCursors.click,
  });
  ButtonStyle button(WidgetStateProperty<Color> background, Color foreground) =>
      ButtonStyle(
        backgroundColor: background,
        foregroundColor: ink(foreground),
        iconColor: ink(foreground),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        mouseCursor: cursor,
        padding: const WidgetStatePropertyAll(padding),
        minimumSize: const WidgetStatePropertyAll(size),
        shape: const WidgetStatePropertyAll(shape),
        iconSize: const WidgetStatePropertyAll(16),
        elevation: const WidgetStatePropertyAll(0),
        side: focusRing,
        animationDuration: const Duration(milliseconds: 120),
        visualDensity: VisualDensity.standard,
      );
  final glyph = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: c.disabledFg,
    WidgetState.selected | WidgetState.hovered: c.text,
    WidgetState.any: c.muted,
  });
  final transparent = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: Colors.transparent,
    WidgetState.pressed: c.neutralHover,
    WidgetState.hovered: c.neutral,
    WidgetState.any: Colors.transparent,
  });
  OutlineInputBorder edge(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: UfRadius.control,
        borderSide: BorderSide(color: color, width: width),
      );
  final checked = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: c.disabledBg,
    WidgetState.selected & WidgetState.hovered: c.accentHover,
    WidgetState.selected: c.accent,
    WidgetState.any: c.field,
  });
  final boxEdge = WidgetStateBorderSide.fromMap({
    WidgetState.disabled: BorderSide(color: c.line),
    WidgetState.focused: BorderSide(color: c.focus, width: 2),
    WidgetState.selected: BorderSide(color: c.accent),
    WidgetState.error: BorderSide(color: c.danger, width: 1.5),
    WidgetState.hovered: BorderSide(color: c.muted),
    WidgetState.any: BorderSide(color: c.edge),
  });
  final menuShadow = Color(c.isDark ? 0x73000000 : 0x1A18201C);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _ui,
    extensions: [c],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.accentFg,
      secondary: c.accentText,
      onSecondary: c.bg,
      error: c.danger,
      onError: c.onDanger,
      surface: c.panel,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      outline: c.edge,
      outlineVariant: c.line,
      surfaceTint: Colors.transparent,
    ),
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    hoverColor: c.panelHover,
    focusColor: Colors.transparent,
    highlightColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.text,
      selectionColor: c.select,
      selectionHandleColor: c.accent,
    ),
    // primary: `accent` fill; secondary: `neutral` fill; quiet: transparent, `neutral` on hover
    filledButtonTheme: FilledButtonThemeData(
      style: button(fill(c.accent, c.accentHover, c.accentPress), c.accentFg),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(fill(c.neutral, c.neutralHover, c.neutralPress), c.text),
    ),
    textButtonTheme: TextButtonThemeData(style: button(transparent, c.text)),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty<Color>.fromMap({
          WidgetState.disabled: Colors.transparent,
          WidgetState.selected: c.panelHover,
          WidgetState.pressed: c.neutralHover,
          WidgetState.hovered: c.neutral,
          WidgetState.any: Colors.transparent,
        }),
        foregroundColor: glyph,
        iconColor: glyph,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        mouseCursor: cursor,
        side: focusRing,
        iconSize: const WidgetStatePropertyAll(16),
        minimumSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
        maximumSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
        fixedSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(shape),
        visualDensity: VisualDensity.compact,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _StateColor({
        WidgetState.disabled: c.disabledBg,
        WidgetState.any: c.field,
      }),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      hintStyle: text.bodyMedium!.copyWith(color: c.muted, fontSize: 13.5),
      helperStyle: text.bodySmall!.copyWith(color: c.muted),
      errorStyle: text.bodySmall!.copyWith(
        color: c.danger,
        fontWeight: FontWeight.w600,
      ),
      // the only border: the state-specific ones would take precedence over it
      border: WidgetStateInputBorder.fromMap({
        WidgetState.disabled: edge(c.line),
        WidgetState.error & WidgetState.focused: edge(c.danger, 2),
        WidgetState.focused: edge(c.focus, 2),
        WidgetState.error: edge(c.danger),
        WidgetState.hovered: edge(c.muted),
        WidgetState.any: edge(c.edge),
      }),
      // icon slots default to 48 px and would stretch the 32 px field
      prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      hoverColor: Colors.transparent,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: checked,
      checkColor: WidgetStateProperty<Color>.fromMap({
        WidgetState.disabled: c.disabledFg,
        WidgetState.any: c.accentFg,
      }),
      side: boxEdge,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const RoundedRectangleBorder(borderRadius: UfRadius.key),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.text, borderRadius: UfRadius.control),
      textStyle: text.bodySmall!.copyWith(color: c.isDark ? c.bg : c.side),
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.panel,
      contentTextStyle: text.bodyMedium,
      actionTextColor: c.accentText,
      behavior: SnackBarBehavior.floating,
      width: 380,
      showCloseIcon: true,
      closeIconColor: c.muted,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: UfRadius.card,
        side: BorderSide(color: c.line),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.panel),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(menuShadow),
        side: WidgetStatePropertyAll(BorderSide(color: c.line)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: UfRadius.card),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        shape: const WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(
          text.bodyMedium!.copyWith(fontSize: 13.5),
        ),
        foregroundColor: ink(c.text),
        iconColor: ink(c.muted),
        backgroundColor: WidgetStateProperty<Color>.fromMap({
          WidgetState.hovered | WidgetState.focused: c.panelHover,
          WidgetState.any: Colors.transparent,
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        mouseCursor: cursor,
      ),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      iconColor: c.muted,
      textColor: c.text,
      selectedColor: c.accentText,
      selectedTileColor: c.select,
      shape: const RoundedRectangleBorder(borderRadius: UfRadius.control),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minTileHeight: UfHeight.medium,
      horizontalTitleGap: 8,
      titleTextStyle: text.bodyMedium!.copyWith(fontSize: 13.5),
      subtitleTextStyle: text.bodySmall!.copyWith(color: c.muted),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.text,
      unselectedLabelColor: c.muted,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
      indicatorColor: c.accent,
      dividerColor: c.line,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      // at tab size the default indicator is a 2 px square underline
      indicatorSize: TabBarIndicatorSize.tab,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      mouseCursor: cursor,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.line,
      circularTrackColor: c.line,
      borderRadius: const BorderRadius.all(Radius.circular(2)),
      strokeWidth: 2,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.edge.withValues(alpha: 0.5)),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: c.panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: UfRadius.card,
        side: BorderSide(color: c.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      elevation: 0,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(borderRadius: UfRadius.dialog),
      titleTextStyle: text.titleLarge,
    ),
  );
}

// A colour per state that is also a real Color, its last value: themes lerp colour slots, which a
// WidgetStateColor.fromMap cannot do.
class _StateColor extends WidgetStateColor {
  _StateColor(WidgetStateMap<Color> map)
    : _states = WidgetStateMapper(map),
      super(map.values.last.toARGB32());

  final WidgetStateMapper<Color> _states;

  @override
  Color resolve(Set<WidgetState> states) => _states.resolve(states);

  @override
  bool operator ==(Object other) =>
      other is _StateColor && other._states == _states;

  @override
  int get hashCode => _states.hashCode;
}
