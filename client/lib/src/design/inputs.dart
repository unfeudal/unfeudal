// SPDX-License-Identifier: Apache-2.0
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

part 'combobox.dart';
part 'search_field.dart';

// A muted glyph button inside a field box: `neutral` on hover with a `text` glyph, radius 4.
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

/// A read-only key, fingerprint or link in mono 12 over several lines, in a 1 px dashed `edge` box with no
/// fill; the value is selectable. With [onCopy] it ends with a copy button, else with a muted lock.
class UfReadOnlyField extends StatelessWidget {
  const UfReadOnlyField({super.key, required this.value, this.onCopy});

  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final copy = onCopy;
    return CustomPaint(
      painter: UfDashedEdge(colors.edge),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: UfHeight.medium),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: monoField.copyWith(color: colors.text),
                ),
              ),
              if (copy != null)
                _FieldIconButton(
                  icon: const Icon(UfIcons.copy),
                  tooltip: MaterialLocalizations.of(context).copyButtonLabel,
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

/// A 1 px dashed edge with the control radius, 4 on and 3 off.
class UfDashedEdge extends CustomPainter {
  const UfDashedEdge(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    final edge = Path()
      ..addRRect(UfRadius.control.toRRect(Offset.zero & size).deflate(0.5));
    for (final metric in edge.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 7) {
        canvas.drawPath(metric.extractPath(at, at + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(UfDashedEdge old) => old.color != color;
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
