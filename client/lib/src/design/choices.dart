// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'icons.dart';
import 'motion.dart';
import 'tokens.dart';

part 'radio.dart';
part 'select.dart';

/// An on/off switch: a 32 by 18 track whose 14 px thumb slides in [UfMotion.base]. Null [onChanged] disables
/// it.
class UfSwitch extends StatelessWidget {
  const UfSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    final disabled = change == null;
    return Semantics(
      toggled: value,
      enabled: !disabled,
      label: semanticLabel,
      child: _Pressable(
        onTap: disabled ? null : () => change(!value),
        builder: (context, states) =>
            _SwitchTrack(value: value, states: states),
      ),
    );
  }
}

class _SwitchTrack extends StatelessWidget {
  const _SwitchTrack({required this.value, required this.states});

  final bool value;
  final Set<WidgetState> states;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final motion = UfMotion.of(context);
    final disabled = states.contains(WidgetState.disabled);
    final active =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    final track = disabled
        ? colors.disabledBg
        : !value
        ? (active ? colors.muted : colors.edge)
        : states.contains(WidgetState.pressed)
        ? colors.accentPress
        : states.contains(WidgetState.hovered)
        ? colors.accentHover
        : colors.accent;
    final thumb = disabled
        ? colors.disabledFg
        : value
        ? colors.accentFg
        : colors.isDark
        ? colors.text
        : colors.panel;
    return AnimatedContainer(
      duration: motion.base,
      curve: UfMotion.standard,
      width: 32,
      height: 18,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: track,
        borderRadius: const BorderRadius.all(Radius.circular(9)),
        boxShadow: states.contains(WidgetState.focused)
            ? UfElevation.focusRing(colors)
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(9)),
        border: disabled ? Border.all(color: colors.line) : null,
      ),
      child: AnimatedAlign(
        duration: motion.base,
        curve: UfMotion.standard,
        alignment: value
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: thumb, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// A 16 px checkbox, then its 13.5 [label] and an optional `muted` [subtitle]; the whole label toggles it.
/// Null [onChanged] disables it.
class UfCheckboxRow extends StatelessWidget {
  const UfCheckboxRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.subtitle,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final change = onChanged;
    return MergeSemantics(
      child: MouseRegion(
        cursor: change == null
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: change == null ? null : () => change(!value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox.square(
                  dimension: 16,
                  // the themed box is 18 px
                  child: Transform.scale(
                    scale: 16 / 18,
                    child: Checkbox(
                      value: value,
                      onChanged: change == null ? null : (v) => change(v!),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: text.bodyMedium!.copyWith(
                        fontSize: 13.5,
                        color: change == null ? colors.disabledFg : colors.text,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: text.bodySmall!.copyWith(color: colors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tracks hover, press and keyboard focus for the switch, radio and select; Enter and Space activate. Null onTap
// reports WidgetState.disabled.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onTap,
    required this.builder,
    this.focusNode,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;
  final FocusNode? focusNode;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false, _focus = false, _press = false;

  void _pressed(bool value) => setState(() => _press = value);

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final enabled = onTap != null;
    return FocusableActionDetector(
      enabled: enabled,
      focusNode: widget.focusNode,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => onTap?.call(),
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: enabled ? (_) => _pressed(true) : null,
        onTapUp: enabled ? (_) => _pressed(false) : null,
        onTapCancel: enabled ? () => _pressed(false) : null,
        child: widget.builder(context, {
          if (!enabled) WidgetState.disabled,
          if (enabled && _hover) WidgetState.hovered,
          if (enabled && _focus) WidgetState.focused,
          if (enabled && _press) WidgetState.pressed,
        }),
      ),
    );
  }
}
