// SPDX-License-Identifier: Apache-2.0
part of 'tokens.dart';

ThemeData ufTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? UfColors.light : UfColors.dark;
  final text = _textTheme(c);
  final (filled, outlined, quiet) = _buttonStyles(c, text);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _ui,
    extensions: [c],
    colorScheme: _colorScheme(c, brightness),
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
    filledButtonTheme: FilledButtonThemeData(style: filled),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlined),
    textButtonTheme: TextButtonThemeData(style: quiet),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(c)),
    inputDecorationTheme: _inputDecorationTheme(c, text),
    checkboxTheme: _checkboxTheme(c),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.text, borderRadius: UfRadius.control),
      textStyle: text.bodySmall!.copyWith(color: c.isDark ? c.bg : c.side),
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    snackBarTheme: _snackBarTheme(c, text),
    menuTheme: _menuTheme(c),
    menuButtonTheme: MenuButtonThemeData(style: _menuButtonStyle(c, text)),
    listTileTheme: _listTileTheme(c, text),
    tabBarTheme: _tabBarTheme(c, text),
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
    cardTheme: _cardTheme(c),
    dialogTheme: _dialogTheme(c, text),
  );
}

TextTheme _textTheme(UfColors c) {
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

ColorScheme _colorScheme(UfColors c, Brightness brightness) => ColorScheme(
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
);

const _controlShape = RoundedRectangleBorder(borderRadius: UfRadius.control);

const _cursor = WidgetStateMouseCursor.fromMap({
  WidgetState.disabled: SystemMouseCursors.forbidden,
  WidgetState.any: SystemMouseCursors.click,
});

WidgetStateProperty<Color> _ink(UfColors c, Color rest) =>
    WidgetStateProperty<Color>.fromMap({
      WidgetState.disabled: c.disabledFg,
      WidgetState.any: rest,
    });

// keyboard focus: a 2 px `focus` stroke outside the shape
WidgetStateBorderSide _focusRing(UfColors c) => WidgetStateBorderSide.fromMap({
  WidgetState.focused: BorderSide(
    color: c.focus,
    width: 2,
    strokeAlign: BorderSide.strokeAlignOutside,
  ),
  WidgetState.any: BorderSide.none,
});

(ButtonStyle, ButtonStyle, ButtonStyle) _buttonStyles(
  UfColors c,
  TextTheme text,
) {
  const padding = EdgeInsets.symmetric(horizontal: 14);
  const size = Size(0, UfHeight.medium);
  // fromMap compares by value: a closure would make every ufTheme() unequal and animate theme changes
  WidgetStateProperty<Color> fill(Color rest, Color hover, Color press) =>
      WidgetStateProperty<Color>.fromMap({
        WidgetState.disabled: c.disabledBg,
        WidgetState.pressed: press,
        WidgetState.hovered: hover,
        WidgetState.any: rest,
      });
  final focusRing = _focusRing(c);
  ButtonStyle button(WidgetStateProperty<Color> background, Color foreground) =>
      ButtonStyle(
        backgroundColor: background,
        foregroundColor: _ink(c, foreground),
        iconColor: _ink(c, foreground),
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
    WidgetState.pressed: c.neutralHover,
    WidgetState.hovered: c.neutral,
    WidgetState.any: Colors.transparent,
  });
  return (
    button(fill(c.accent, c.accentHover, c.accentPress), c.accentFg),
    button(fill(c.neutral, c.neutralHover, c.neutralPress), c.text),
    button(transparent, c.text),
  );
}

ButtonStyle _iconButtonStyle(UfColors c) {
  final glyph = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: c.disabledFg,
    WidgetState.selected | WidgetState.hovered: c.text,
    WidgetState.any: c.muted,
  });
  return ButtonStyle(
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
    mouseCursor: _cursor,
    side: _focusRing(c),
    iconSize: const WidgetStatePropertyAll(16),
    minimumSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
    maximumSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
    fixedSize: const WidgetStatePropertyAll(Size.square(UfHeight.small)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: const WidgetStatePropertyAll(_controlShape),
    visualDensity: VisualDensity.compact,
  );
}

InputDecorationTheme _inputDecorationTheme(UfColors c, TextTheme text) {
  OutlineInputBorder edge(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: UfRadius.control,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecorationTheme(
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
  );
}

CheckboxThemeData _checkboxTheme(UfColors c) => CheckboxThemeData(
  fillColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: c.disabledBg,
    WidgetState.selected & WidgetState.hovered: c.accentHover,
    WidgetState.selected: c.accent,
    WidgetState.any: c.field,
  }),
  checkColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: c.disabledFg,
    WidgetState.any: c.accentFg,
  }),
  side: WidgetStateBorderSide.fromMap({
    WidgetState.disabled: BorderSide(color: c.line),
    WidgetState.focused: BorderSide(color: c.focus, width: 2),
    WidgetState.selected: BorderSide(color: c.accent),
    WidgetState.error: BorderSide(color: c.danger, width: 1.5),
    WidgetState.hovered: BorderSide(color: c.muted),
    WidgetState.any: BorderSide(color: c.edge),
  }),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  shape: const RoundedRectangleBorder(borderRadius: UfRadius.key),
);

SnackBarThemeData _snackBarTheme(UfColors c, TextTheme text) =>
    SnackBarThemeData(
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
    );

MenuThemeData _menuTheme(UfColors c) => MenuThemeData(
  style: MenuStyle(
    backgroundColor: WidgetStatePropertyAll(c.panel),
    elevation: const WidgetStatePropertyAll(8),
    shadowColor: WidgetStatePropertyAll(
      Color(c.isDark ? 0x73000000 : 0x1A18201C),
    ),
    side: WidgetStatePropertyAll(BorderSide(color: c.line)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: UfRadius.card),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
  ),
);

ButtonStyle _menuButtonStyle(UfColors c, TextTheme text) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
  shape: const WidgetStatePropertyAll(_controlShape),
  textStyle: WidgetStatePropertyAll(text.bodyMedium!.copyWith(fontSize: 13.5)),
  foregroundColor: _ink(c, c.text),
  iconColor: _ink(c, c.muted),
  backgroundColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.hovered | WidgetState.focused: c.panelHover,
    WidgetState.any: Colors.transparent,
  }),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  mouseCursor: _cursor,
);

ListTileThemeData _listTileTheme(UfColors c, TextTheme text) =>
    ListTileThemeData(
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
    );

TabBarThemeData _tabBarTheme(UfColors c, TextTheme text) => TabBarThemeData(
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
  mouseCursor: _cursor,
);

CardThemeData _cardTheme(UfColors c) => CardThemeData(
  elevation: 0,
  color: c.panel,
  margin: EdgeInsets.zero,
  shape: RoundedRectangleBorder(
    borderRadius: UfRadius.card,
    side: BorderSide(color: c.line),
  ),
);

DialogThemeData _dialogTheme(UfColors c, TextTheme text) => DialogThemeData(
  backgroundColor: c.panel,
  elevation: 0,
  barrierColor: c.scrim,
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
