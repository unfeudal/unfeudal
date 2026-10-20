// SPDX-License-Identifier: Apache-2.0
import 'dart:ui' show PathMetric;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../loquet/loquet_pose.dart';
import '../loquet/loquet_spot.dart';
import 'field.dart';
import 'icons.dart';
import 'motion.dart';
import 'tokens.dart';

/// A 32 px icon-only quiet button; [tooltip] is also its accessible label. Null [onPressed] disables it.
class UfIconButton extends StatelessWidget {
  const UfIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final ink = WidgetStateProperty<Color>.fromMap({
      WidgetState.disabled: colors.disabledFg,
      WidgetState.any: colors.text,
    });
    const size = WidgetStatePropertyAll(Size.square(UfHeight.medium));
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: ButtonStyle(
        fixedSize: size,
        minimumSize: size,
        maximumSize: size,
        foregroundColor: ink,
        iconColor: ink,
      ),
      icon: Icon(icon),
    );
  }
}

/// A muted glyph button inside a field box: `neutral` on hover with a `text` glyph, radius 4.
class _FieldIconButton extends StatelessWidget {
  const _FieldIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Size size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: ButtonStyle(
      fixedSize: WidgetStatePropertyAll(size),
      minimumSize: WidgetStatePropertyAll(size),
      maximumSize: WidgetStatePropertyAll(size),
      iconSize: WidgetStatePropertyAll(iconSize),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: UfRadius.key),
      ),
    ),
    icon: icon,
  );
}

/// A read-only value in a 1 px dashed `edge` box with no fill; the value is selectable. With [onCopy] it ends
/// with a copy button, else with a muted lock. [mono] writes a key or fingerprint in mono 12 over several lines.
class UfReadOnlyField extends StatelessWidget {
  const UfReadOnlyField({
    super.key,
    required this.value,
    this.mono = false,
    this.onCopy,
    this.copyTooltip,
  });

  final String value;
  final bool mono;
  final VoidCallback? onCopy;

  /// Defaults to the generic "Copy".
  final String? copyTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final style = mono
        ? monoField.copyWith(color: colors.text)
        : Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13.5);
    final copy = onCopy;
    return CustomPaint(
      painter: _DashedEdge(colors.edge),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: UfHeight.medium),
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, mono ? 6 : 0, 6, mono ? 6 : 0),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: style,
                  maxLines: mono ? null : 1,
                ),
              ),
              if (copy != null)
                _FieldIconButton(
                  icon: const Icon(UfIcons.copy),
                  tooltip:
                      copyTooltip ?? AppLocalizations.of(context).fieldCopy,
                  onPressed: copy,
                  size: const Size.square(21),
                  iconSize: 15,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(UfIcons.lock, size: 14, color: colors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 1 px dashed rounded edge, 4 on and 3 off.
class _DashedEdge extends CustomPainter {
  const _DashedEdge(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    final edge = Path()
      ..addRRect(UfRadius.control.toRRect(Offset.zero & size).deflate(0.5));
    for (final PathMetric metric in edge.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 7) {
        canvas.drawPath(metric.extractPath(at, at + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) => old.color != color;
}

/// Four segments under a password field, [score] of them filled in `ok`, then the strength word and the
/// Caps Lock state in 12 muted. [score] runs from 0 (empty) to 4.
class UfStrengthMeter extends StatelessWidget {
  const UfStrengthMeter({
    super.key,
    required this.score,
    required this.capsLock,
  });

  final int score;
  final bool capsLock;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final l = AppLocalizations.of(context);
    final word = switch (score) {
      <= 0 => null,
      1 => l.strengthWeak,
      2 => l.strengthFair,
      3 => l.strengthGood,
      _ => l.strengthStrong,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            spacing: 4,
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    key: Key('strength-$i'),
                    height: 3,
                    decoration: BoxDecoration(
                      color: i < score ? colors.ok : colors.line,
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(
          [?word, capsLock ? l.capsLockOn : l.capsLockOff].join(' '),
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// [text] with every case-insensitive occurrence of [query] in 600.
class UfMatchText extends StatelessWidget {
  const UfMatchText(this.text, {super.key, required this.query, this.style});

  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase(), needle = query.toLowerCase();
    // a lowercase that changes the length would shift the bold run
    if (needle.isEmpty || lower.length != text.length) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final spans = <TextSpan>[];
    var from = 0;
    for (
      var at = lower.indexOf(needle);
      at >= 0;
      at = lower.indexOf(needle, from)
    ) {
      if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
      from = at + needle.length;
      spans.add(
        TextSpan(
          text: text.substring(at, from),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// No result for [query]: Loquet searching at 40 px over "Nothing matches « q »." in 13 muted, centred.
class UfNoMatch extends StatelessWidget {
  const UfNoMatch({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        const LoquetSpot(
          placement: LoquetPlacement.dialog,
          mood: LoquetMood.search,
        ),
        Text(
          AppLocalizations.of(context).searchNoMatch(query),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(fontSize: 13, color: UfColors.of(context).muted),
        ),
      ],
    ),
  );
}

/// A search box: a muted magnifier, then the text, then a kbd chip showing [shortcut] at rest and Esc while
/// focused; the shortcut hides once the field holds text. Escape clears the text, then calls [onEscape], which
/// defaults to leaving the field.
class UfSearchField extends StatefulWidget {
  const UfSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.shortcut,
    this.onChanged,
    this.onEscape,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;

  /// The shortcut that reaches the field, written out ("Ctrl K"); null shows no chip at rest.
  final String? shortcut;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEscape;
  final bool autofocus;

  @override
  State<UfSearchField> createState() => _UfSearchFieldState();
}

class _UfSearchFieldState extends State<UfSearchField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    _controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(UfSearchField old) {
    super.didUpdateWidget(old);
    final oldFocus = old.focusNode ?? _ownFocus;
    if (oldFocus != _focus) {
      oldFocus?.removeListener(_refresh);
      _focus.addListener(_refresh);
    }
    final oldController = old.controller ?? _ownController;
    if (oldController != _controller) {
      oldController?.removeListener(_refresh);
      _controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _controller.removeListener(_refresh);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      widget.onChanged?.call('');
    } else if (widget.onEscape case final escape?) {
      escape();
    } else {
      _focus.unfocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final muted = UfColors.of(context).muted;
    final kbd = _focus.hasFocus
        ? AppLocalizations.of(context).keyEscape
        : _controller.text.isEmpty
        ? widget.shortcut
        : null;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Icon(UfIcons.magnifyingGlass, size: 14, color: muted),
          ),
          prefixIconConstraints: const BoxConstraints(),
          suffixIcon: kbd == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: UfKbd(kbd),
                ),
          suffixIconConstraints: const BoxConstraints(),
        ),
      ),
    );
  }
}

/// A whole number in mono 12 with stacked up and down chevrons; the arrow keys and the mouse wheel step it,
/// clamped to [min]..[max]. An emptied field reports null, for a value that is unset or inherited; it then
/// shows [placeholder] greyed, and steps from it. Null [onChanged] disables it.
class UfNumberField extends StatefulWidget {
  const UfNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 65535,
    this.width = 132,
    this.placeholder,
  });

  final int? value;
  final ValueChanged<int?>? onChanged;
  final int min, max;
  final double width;
  final int? placeholder;

  @override
  State<UfNumberField> createState() => _UfNumberFieldState();
}

class _UfNumberFieldState extends State<UfNumberField> {
  late final _controller = TextEditingController(text: _text(widget.value));
  final _focus = FocusNode();

  // ahead of widget.value until the parent rebuilds: several steps within a frame add up
  late int? _value = widget.value;

  static String _text(int? value) => value == null ? '' : '$value';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(UfNumberField old) {
    super.didUpdateWidget(old);
    _value = widget.value;
    if (int.tryParse(_controller.text) != widget.value) {
      _controller.text = _text(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // a value typed out of range snaps back into it when the field is left
  void _onFocus() {
    if (!_focus.hasFocus) _controller.text = _text(widget.value);
  }

  void _set(int value) {
    final clamped = value.clamp(widget.min, widget.max);
    if (clamped == _value) return;
    _value = clamped;
    widget.onChanged?.call(clamped);
  }

  void _typed(String text) {
    final value = int.tryParse(text);
    if (text.isEmpty ||
        (value != null && value >= widget.min && value <= widget.max)) {
      _value = value;
      widget.onChanged?.call(value);
    }
  }

  void _step(int by) => _set((_value ?? widget.placeholder ?? widget.min) + by);

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final by = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => 1,
      LogicalKeyboardKey.arrowDown => -1,
      _ => 0,
    };
    if (by == 0) return KeyEventResult.ignored;
    _step(by);
    return KeyEventResult.handled;
  }

  void _onWheel(PointerSignalEvent event) {
    // only while focused: a wheel passing over the field scrolls the page instead
    if (event is! PointerScrollEvent ||
        widget.onChanged == null ||
        !_focus.hasFocus) {
      return;
    }
    // claimed, so a scrollable around the field stays put
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy != 0) _step(dy < 0 ? 1 : -1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = widget.onChanged != null;
    Widget chevron(int turns, String tooltip, int by) => _FieldIconButton(
      icon: RotatedBox(
        quarterTurns: turns,
        child: const Icon(UfIcons.caretDown),
      ),
      tooltip: tooltip,
      onPressed: enabled ? () => _step(by) : null,
      size: const Size(16, 12),
      iconSize: 12,
    );
    return SizedBox(
      width: widget.width,
      child: Listener(
        onPointerSignal: _onWheel,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: enabled,
            onChanged: _typed,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(widget.min < 0 ? r'^-?\d*' : r'^\d*'),
              ),
            ],
            style: monoField,
            decoration: InputDecoration(
              hintText: widget.placeholder?.toString(),
              suffixIcon: ExcludeFocus(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      chevron(2, l.fieldIncrease, 1),
                      chevron(0, l.fieldDecrease, -1),
                    ],
                  ),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(),
            ),
          ),
        ),
      ),
    );
  }
}

/// One option of a [UfCombobox]; a [disabledReason] disables it and shows as its sub-text instead of [detail].
class UfComboOption<T> {
  const UfComboOption(
    this.value,
    this.label, {
    this.detail,
    this.disabledReason,
  });

  final T value;
  final String label;
  final String? detail;
  final String? disabledReason;

  bool get isEnabled => disabledReason == null;
}

/// A field you type into to filter a long option list that opens 4 px below it; the match is bold. The arrows
/// move through enabled options, Enter picks, Escape closes. [value] shows its option's label in the field.
class UfCombobox<T> extends StatefulWidget {
  const UfCombobox({
    super.key,
    required this.options,
    required this.onSelected,
    this.value,
    this.hint,
  });

  final List<UfComboOption<T>> options;
  final ValueChanged<T> onSelected;
  final T? value;
  final String? hint;

  @override
  State<UfCombobox<T>> createState() => _UfComboboxState<T>();
}

class _UfComboboxState<T> extends State<UfCombobox<T>>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _activeRow = GlobalKey();
  late final _fade = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _portal.hide();
    });
  late final _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: UfMotion.enter,
    reverseCurve: UfMotion.exit,
  );
  var _query = '';
  var _active = -1;
  var _width = 0.0;

  List<UfComboOption<T>> get _shown => [
    for (final o in widget.options)
      if (o.label.toLowerCase().contains(_query.toLowerCase())) o,
  ];

  @override
  void initState() {
    super.initState();
    _controller.text = _labelOf(widget.value) ?? '';
    _focus.addListener(() {
      if (!_focus.hasFocus) _close();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = UfMotion.of(context);
    _fade
      ..duration = motion.base
      ..reverseDuration = motion.fast;
  }

  @override
  void didUpdateWidget(UfCombobox<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _controller.text = _labelOf(widget.value) ?? '';
    }
  }

  @override
  void dispose() {
    _fadeCurve.dispose();
    _fade.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _labelOf(T? value) {
    for (final o in widget.options) {
      if (o.value == value) return o.label;
    }
    return null;
  }

  bool get _isOpen => _fade.status.isForwardOrCompleted;

  void _open() {
    if (_isOpen) return;
    _width = context.size?.width ?? 0;
    _portal.show();
    _fade.forward();
  }

  void _close() {
    if (_isOpen) _fade.reverse();
  }

  void _typed(String text) {
    setState(() {
      _query = text;
      _active = _shown.indexWhere((o) => o.isEnabled);
    });
    _open();
  }

  void _pick(UfComboOption<T> option) {
    if (!option.isEnabled) return;
    _controller.text = option.label;
    setState(() => _query = '');
    _close();
    widget.onSelected(option.value);
  }

  void _move(int by) {
    final shown = _shown;
    for (var i = 1; i <= shown.length; i++) {
      final at = (_active + by * i) % shown.length;
      if (shown[at].isEnabled) {
        setState(() => _active = at);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final row = _activeRow.currentContext;
          if (row != null && row.mounted) Scrollable.ensureVisible(row);
        });
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp:
        final by = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
        if (!_isOpen) {
          _open();
          setState(() => _active = _shown.indexWhere((o) => o.isEnabled));
        } else {
          _move(by);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        final shown = _shown;
        if (!_isOpen || _active < 0 || _active >= shown.length) {
          return KeyEventResult.ignored;
        }
        _pick(shown[_active]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape when _isOpen:
        _close();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13.5);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned(
          width: _width,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 4),
            child: TextFieldTapRegion(
              child: FadeTransition(
                opacity: _fadeCurve,
                child: _list(colors, text),
              ),
            ),
          ),
        ),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            onChanged: _typed,
            onTap: _open,
            style: text,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 10, right: 8),
                child: Icon(
                  UfIcons.magnifyingGlass,
                  size: 14,
                  color: colors.muted,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(UfColors colors, TextStyle text) {
    final shown = _shown;
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: UfRadius.card,
        boxShadow: UfElevation.floating(colors),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: shown.isEmpty
              ? Center(child: UfNoMatch(query: _query))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 1,
                  children: [
                    for (final (i, option) in shown.indexed)
                      _comboRow(colors, text, option, i),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _comboRow(
    UfColors colors,
    TextStyle text,
    UfComboOption<T> option,
    int index,
  ) {
    final active = index == _active;
    final sub = option.disabledReason ?? option.detail;
    return Semantics(
      key: active ? _activeRow : null,
      button: true,
      selected: active,
      enabled: option.isEnabled,
      child: MouseRegion(
        cursor: option.isEnabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: option.isEnabled
            ? (_) => setState(() => _active = index)
            : null,
        child: GestureDetector(
          onTap: () => _pick(option),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active ? colors.panelHover : null,
              borderRadius: UfRadius.control,
            ),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: UfMatchText(
                    option.label,
                    query: _query,
                    style: text.copyWith(
                      color: option.isEnabled ? colors.text : colors.disabledFg,
                    ),
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: text.copyWith(
                      fontSize: 12,
                      color: option.isEnabled
                          ? colors.muted
                          : colors.disabledFg,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 20 px slider: a 4 px `line` track filled in `accent` up to a 14 px knob; while dragged the knob gets a
/// `select` halo and a value tip 28 px above it. The arrow keys step it. Null [onChanged] disables it.
class UfSlider extends StatefulWidget {
  const UfSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min, max;

  /// Snaps the value to this many equal steps; the arrow keys move one step, or a twentieth without it.
  final int? divisions;

  /// Writes the value in the tip and for screen readers; defaults to the rounded value.
  final String Function(double value)? label;
  final String? semanticLabel;

  @override
  State<UfSlider> createState() => _UfSliderState();
}

class _UfSliderState extends State<UfSlider> {
  static const _knob = 14.0;
  bool _dragging = false, _focused = false;

  double get _span => widget.max - widget.min;
  double get _step => _span / (widget.divisions ?? 20);

  String _label(double value) =>
      widget.label?.call(value) ?? value.round().toString();

  void _set(double value) {
    var v = value.clamp(widget.min, widget.max).toDouble();
    if (widget.divisions case final divisions?) {
      v =
          widget.min +
          ((v - widget.min) / _span * divisions).round() * _span / divisions;
    }
    if (v != widget.value) widget.onChanged?.call(v);
  }

  void _setAt(double dx, double width) => _set(
    widget.min + ((dx - _knob / 2) / (width - _knob)).clamp(0, 1) * _span,
  );

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final enabled = widget.onChanged != null;
    final tip = Theme.of(context).tooltipTheme;
    final t = _span == 0 ? 0.0 : (widget.value - widget.min) / _span;
    void step(double by) => _set(widget.value + by);
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: _label(widget.value),
      increasedValue: _label(
        (widget.value + _step).clamp(widget.min, widget.max).toDouble(),
      ),
      decreasedValue: _label(
        (widget.value - _step).clamp(widget.min, widget.max).toDouble(),
      ),
      onIncrease: enabled ? () => step(_step) : null,
      onDecrease: enabled ? () => step(-_step) : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(-1),
        },
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(
            onInvoke: (intent) => step(intent.direction * _step),
          ),
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final x = t * (width - _knob);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled
                  ? (d) => _setAt(d.localPosition.dx, width)
                  : null,
              onHorizontalDragStart: enabled
                  ? (d) {
                      setState(() => _dragging = true);
                      _setAt(d.localPosition.dx, width);
                    }
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (d) => _setAt(d.localPosition.dx, width)
                  : null,
              onHorizontalDragEnd: enabled
                  ? (_) => setState(() => _dragging = false)
                  : null,
              onHorizontalDragCancel: enabled
                  ? () => setState(() => _dragging = false)
                  : null,
              child: SizedBox(
                height: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.line,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                      ),
                    ),
                    Container(
                      width: x + _knob / 2,
                      height: 4,
                      decoration: BoxDecoration(
                        color: enabled ? colors.accent : colors.disabledFg,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: x,
                      child: Container(
                        width: _knob,
                        height: _knob,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !enabled
                              ? colors.disabledBg
                              : colors.isDark
                              ? colors.text
                              : colors.panel,
                          border: Border.all(
                            color: enabled ? colors.accent : colors.disabledFg,
                            width: 1.5,
                          ),
                          boxShadow: [
                            if (_focused)
                              BoxShadow(color: colors.focus, spreadRadius: 2)
                            else if (_dragging)
                              BoxShadow(color: colors.select, spreadRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    if (_dragging)
                      Positioned(
                        key: const Key('slider-tip'),
                        left: x + _knob / 2 - 16,
                        top: -28 + 3,
                        child: Container(
                          width: 32,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: (tip.decoration! as BoxDecoration)
                              .copyWith(borderRadius: UfRadius.key),
                          child: Text(
                            _label(widget.value),
                            maxLines: 1,
                            style: tip.textStyle!.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.direction);

  final int direction;
}
