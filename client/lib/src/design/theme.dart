// SPDX-License-Identifier: Apache-2.0
part of 'tokens.dart';

ThemeData ufTheme(Brightness brightness) {
  final colors = brightness == Brightness.light
      ? UfColors.light
      : UfColors.dark;
  final text = _textTheme(colors);
  final (filled, outlined, quiet) = _buttonStyles(colors, text);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _ui,
    extensions: [colors],
    colorScheme: _colorScheme(colors, brightness),
    scaffoldBackgroundColor: colors.bg,
    canvasColor: colors.bg,
    dividerColor: colors.line,
    dividerTheme: DividerThemeData(color: colors.line, thickness: 1, space: 1),
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    hoverColor: colors.panelHover,
    focusColor: Colors.transparent,
    highlightColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.text,
      selectionColor: colors.select,
      selectionHandleColor: colors.accent,
    ),
    // primary: `accent` fill; secondary: `neutral` fill; quiet: transparent, `neutral` on hover
    filledButtonTheme: FilledButtonThemeData(style: filled),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlined),
    textButtonTheme: TextButtonThemeData(style: quiet),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(colors)),
    inputDecorationTheme: _inputDecorationTheme(colors, text),
    checkboxTheme: _checkboxTheme(colors),
    tooltipTheme: _tooltipTheme(colors, text),
    snackBarTheme: _snackBarTheme(colors, text),
    menuTheme: _menuTheme(colors),
    menuButtonTheme: MenuButtonThemeData(style: _menuButtonStyle(colors, text)),
    listTileTheme: _listTileTheme(colors, text),
    tabBarTheme: _tabBarTheme(colors, text),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.line,
      circularTrackColor: colors.line,
      borderRadius: const BorderRadius.all(Radius.circular(2)),
      strokeWidth: 2,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors.edge.withValues(alpha: 0.5)),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    cardTheme: _cardTheme(colors),
    dialogTheme: _dialogTheme(colors, text),
  );
}

TextTheme _textTheme(UfColors colors) {
  TextStyle title(double size, double height) => TextStyle(
    fontFamily: _titles,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: height,
    color: colors.text,
  );
  // only 400 and 600 are bundled
  TextStyle ui(double size, [FontWeight weight = FontWeight.w400]) => TextStyle(
    fontFamily: _ui,
    fontSize: size,
    fontWeight: weight,
    height: 1.45,
    fontFeatures: _tabular,
    color: colors.text,
  );
  return TextTheme(
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
}

ColorScheme _colorScheme(UfColors colors, Brightness brightness) => ColorScheme(
  brightness: brightness,
  primary: colors.accent,
  onPrimary: colors.accentFg,
  secondary: colors.accentText,
  onSecondary: colors.bg,
  error: colors.danger,
  onError: colors.onDanger,
  surface: colors.panel,
  onSurface: colors.text,
  onSurfaceVariant: colors.muted,
  outline: colors.edge,
  outlineVariant: colors.line,
  surfaceTint: Colors.transparent,
);

const _controlShape = RoundedRectangleBorder(borderRadius: UfRadius.control);

const _cursor = WidgetStateMouseCursor.fromMap({
  WidgetState.disabled: SystemMouseCursors.forbidden,
  WidgetState.any: SystemMouseCursors.click,
});

WidgetStateProperty<Color> _ink(UfColors colors, Color rest) =>
    WidgetStateProperty<Color>.fromMap({
      WidgetState.disabled: colors.disabledFg,
      WidgetState.any: rest,
    });

// keyboard focus: a 2 px `focus` stroke outside the shape
WidgetStateBorderSide _focusRing(UfColors colors) =>
    WidgetStateBorderSide.fromMap({
      WidgetState.focused: BorderSide(
        color: colors.focus,
        width: 2,
        strokeAlign: BorderSide.strokeAlignOutside,
      ),
      WidgetState.any: BorderSide.none,
    });

(ButtonStyle, ButtonStyle, ButtonStyle) _buttonStyles(
  UfColors colors,
  TextTheme text,
) {
  const padding = EdgeInsets.symmetric(horizontal: 14);
  const size = Size(0, UfHeight.medium);
  // fromMap compares by value: a closure would make every ufTheme() unequal and animate theme changes
  WidgetStateProperty<Color> fill(Color rest, Color hover, Color press) =>
      WidgetStateProperty<Color>.fromMap({
        WidgetState.disabled: colors.disabledBg,
        WidgetState.pressed: press,
        WidgetState.hovered: hover,
        WidgetState.any: rest,
      });
  final focusRing = _focusRing(colors);
  ButtonStyle button(WidgetStateProperty<Color> background, Color foreground) =>
      ButtonStyle(
        backgroundColor: background,
        foregroundColor: _ink(colors, foreground),
        iconColor: _ink(colors, foreground),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        mouseCursor: _cursor,
        padding: const WidgetStatePropertyAll(padding),
        minimumSize: const WidgetStatePropertyAll(size),
        shape: const WidgetStatePropertyAll(_controlShape),
        iconSize: const WidgetStatePropertyAll(16),
        elevation: const WidgetStatePropertyAll(0),
        side: focusRing,
        animationDuration: const Duration(milliseconds: 120),
        visualDensity: VisualDensity.standard,
      );
  final transparent = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: Colors.transparent,
    WidgetState.pressed: colors.neutralHover,
    WidgetState.hovered: colors.neutral,
    WidgetState.any: Colors.transparent,
  });
  return (
    button(
      fill(colors.accent, colors.accentHover, colors.accentPress),
      colors.accentFg,
    ),
    button(
      fill(colors.neutral, colors.neutralHover, colors.neutralPress),
      colors.text,
    ),
    button(transparent, colors.text),
  );
}

ButtonStyle _iconButtonStyle(UfColors colors) {
  final glyph = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledFg,
    WidgetState.selected | WidgetState.hovered: colors.text,
    WidgetState.any: colors.muted,
  });
  return ButtonStyle(
    backgroundColor: WidgetStateProperty<Color>.fromMap({
      WidgetState.disabled: Colors.transparent,
      WidgetState.selected: colors.panelHover,
      WidgetState.pressed: colors.neutralHover,
      WidgetState.hovered: colors.neutral,
      WidgetState.any: Colors.transparent,
    }),
    foregroundColor: glyph,
    iconColor: glyph,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    mouseCursor: _cursor,
    side: _focusRing(colors),
    iconSize: const WidgetStatePropertyAll(16),
    minimumSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
    maximumSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
    fixedSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: const WidgetStatePropertyAll(_controlShape),
    visualDensity: VisualDensity.compact,
  );
}

InputDecorationTheme _inputDecorationTheme(UfColors colors, TextTheme text) {
  OutlineInputBorder edge(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: UfRadius.control,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecorationTheme(
    filled: true,
    fillColor: _StateColor({
      WidgetState.disabled: colors.disabledBg,
      WidgetState.any: colors.field,
    }),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    hintStyle: text.bodyMedium!.copyWith(color: colors.muted, fontSize: 13.5),
    helperStyle: text.bodySmall!.copyWith(color: colors.muted),
    errorStyle: text.bodySmall!.copyWith(
      color: colors.danger,
      fontWeight: FontWeight.w600,
    ),
    // the only border: the state-specific ones would take precedence over it
    border: WidgetStateInputBorder.fromMap({
      WidgetState.disabled: edge(colors.line),
      WidgetState.error & WidgetState.focused: edge(colors.danger, 2),
      WidgetState.focused: edge(colors.focus, 2),
      WidgetState.error: edge(colors.danger),
      WidgetState.hovered: edge(colors.muted),
      WidgetState.any: edge(colors.edge),
    }),
    // icon slots default to 48 px and would stretch the 32 px field
    prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    hoverColor: Colors.transparent,
  );
}

CheckboxThemeData _checkboxTheme(UfColors colors) => CheckboxThemeData(
  fillColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledBg,
    WidgetState.selected & WidgetState.hovered: colors.accentHover,
    WidgetState.selected: colors.accent,
    WidgetState.any: colors.field,
  }),
  checkColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledFg,
    WidgetState.any: colors.accentFg,
  }),
  side: WidgetStateBorderSide.fromMap({
    WidgetState.disabled: BorderSide(color: colors.line),
    WidgetState.focused: BorderSide(color: colors.focus, width: 2),
    WidgetState.selected: BorderSide(color: colors.accent),
    WidgetState.error: BorderSide(color: colors.danger, width: 1.5),
    WidgetState.hovered: BorderSide(color: colors.muted),
    WidgetState.any: BorderSide(color: colors.edge),
  }),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  shape: const RoundedRectangleBorder(borderRadius: UfRadius.key),
);

TooltipThemeData _tooltipTheme(UfColors colors, TextTheme text) =>
    TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.text,
        borderRadius: UfRadius.control,
      ),
      textStyle: text.bodySmall!.copyWith(
        color: colors.isDark ? colors.bg : colors.side,
      ),
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );

SnackBarThemeData _snackBarTheme(UfColors colors, TextTheme text) =>
    SnackBarThemeData(
      backgroundColor: colors.panel,
      contentTextStyle: text.bodyMedium,
      actionTextColor: colors.accentText,
      behavior: SnackBarBehavior.floating,
      width: 380,
      showCloseIcon: true,
      closeIconColor: colors.muted,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: UfRadius.card,
        side: BorderSide(color: colors.line),
      ),
    );

MenuThemeData _menuTheme(UfColors colors) => MenuThemeData(
  style: MenuStyle(
    backgroundColor: WidgetStatePropertyAll(colors.panel),
    elevation: const WidgetStatePropertyAll(8),
    shadowColor: WidgetStatePropertyAll(_floatingShadow(colors)),
    side: WidgetStatePropertyAll(BorderSide(color: colors.line)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: UfRadius.card),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
  ),
);

ButtonStyle _menuButtonStyle(UfColors colors, TextTheme text) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
  shape: const WidgetStatePropertyAll(_controlShape),
  textStyle: WidgetStatePropertyAll(text.bodyMedium!.copyWith(fontSize: 13.5)),
  foregroundColor: _ink(colors, colors.text),
  iconColor: _ink(colors, colors.muted),
  backgroundColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.hovered | WidgetState.focused: colors.panelHover,
    WidgetState.any: Colors.transparent,
  }),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  mouseCursor: _cursor,
);

ListTileThemeData _listTileTheme(UfColors colors, TextTheme text) =>
    ListTileThemeData(
      dense: true,
      iconColor: colors.muted,
      textColor: colors.text,
      selectedColor: colors.accentText,
      selectedTileColor: colors.select,
      shape: const RoundedRectangleBorder(borderRadius: UfRadius.control),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minTileHeight: UfHeight.medium,
      horizontalTitleGap: 8,
      titleTextStyle: text.bodyMedium!.copyWith(fontSize: 13.5),
      subtitleTextStyle: text.bodySmall!.copyWith(color: colors.muted),
    );

TabBarThemeData _tabBarTheme(UfColors colors, TextTheme text) =>
    TabBarThemeData(
      labelColor: colors.text,
      unselectedLabelColor: colors.muted,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
      indicatorColor: colors.accent,
      dividerColor: colors.line,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      // at tab size the default indicator is a 2 px square underline
      indicatorSize: TabBarIndicatorSize.tab,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      mouseCursor: _cursor,
    );

CardThemeData _cardTheme(UfColors colors) => CardThemeData(
  elevation: 0,
  color: colors.panel,
  margin: EdgeInsets.zero,
  shape: RoundedRectangleBorder(
    borderRadius: UfRadius.card,
    side: BorderSide(color: colors.line),
  ),
);

DialogThemeData _dialogTheme(UfColors colors, TextTheme text) =>
    DialogThemeData(
      backgroundColor: colors.panel,
      elevation: 0,
      barrierColor: colors.scrim,
      shape: const RoundedRectangleBorder(borderRadius: UfRadius.dialog),
      titleTextStyle: text.titleLarge,
    );

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
