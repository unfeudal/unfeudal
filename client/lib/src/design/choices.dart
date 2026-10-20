// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'icons.dart';
import 'motion.dart';
import 'tokens.dart';

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
    final colors = UfColors.of(context);
    final motion = UfMotion.of(context);
    final change = onChanged;
    final disabled = change == null;
    return Semantics(
      toggled: value,
      enabled: !disabled,
      label: semanticLabel,
      child: _Pressable(
        onTap: disabled ? null : () => change(!value),
        builder: (context, states) {
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
        },
      ),
    );
  }
}

/// A radio button for [value] among a group whose pick is [groupValue]; with a [label], the whole row picks it.
/// Null [onChanged] disables it.
class UfRadio<T> extends StatelessWidget {
  const UfRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
  });

  final T value;
  final T groupValue;
  final ValueChanged<T>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final pick = onChanged;
    final selected = value == groupValue;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        enabled: pick != null,
        child: _Pressable(
          onTap: pick == null ? null : () => pick(value),
          builder: (context, states) {
            final dot = _RadioDot(selected: selected, states: states);
            final text = label;
            if (text == null) return dot;
            return Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                dot,
                Flexible(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: 13.5,
                      color: pick == null ? colors.disabledFg : colors.text,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A radio choice as a card, for a choice with consequences: the radio, then a 600 [title]; the picked card
/// takes `select` and an `accent` edge.
class UfChoiceCard<T> extends StatelessWidget {
  const UfChoiceCard({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
  });

  final T value;
  final T groupValue;
  final ValueChanged<T>? onChanged;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final pick = onChanged;
    final selected = value == groupValue;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        enabled: pick != null,
        child: _Pressable(
          onTap: pick == null ? null : () => pick(value),
          builder: (context, states) {
            final hovered = states.contains(WidgetState.hovered);
            return AnimatedContainer(
              duration: UfMotion.of(context).fast,
              curve: UfMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? colors.select
                    : hovered
                    ? colors.fieldHover
                    : Colors.transparent,
                borderRadius: UfRadius.card,
                border: Border.all(
                  color: selected
                      ? colors.accent
                      : hovered
                      ? colors.edge
                      : colors.line,
                ),
                boxShadow: states.contains(WidgetState.focused)
                    ? UfElevation.focusRing(colors)
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _RadioDot(
                      selected: selected,
                      states: states.difference({WidgetState.focused}),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: text.labelLarge!.copyWith(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            );
          },
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

/// One option of a [UfSelect]; its [key] goes on the option's menu row. A [style] (a font family to preview)
/// is merged into its label, in the menu and in the box.
class UfOption<T> {
  const UfOption(
    this.value,
    this.label, {
    this.key,
    this.enabled = true,
    this.style,
  });

  final T value;
  final String label;
  final Key? key;
  final bool enabled;
  final TextStyle? style;
}

/// A select: a 32 px field box showing the picked option, opening a menu as wide as itself. It fills a bounded
/// width, else fits its widest label. Null [onChanged] disables it; with no matching option the box is empty;
/// [selectedLabel] replaces the picked option's label in the box.
class UfSelect<T> extends StatefulWidget {
  const UfSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.selectedLabel,
  });

  final List<UfOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? selectedLabel;

  @override
  State<UfSelect<T>> createState() => _UfSelectState<T>();
}

class _UfSelectState<T> extends State<UfSelect<T>> {
  final _menu = MenuController();
  final _focus = FocusNode();
  double _width = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _toggle(BuildContext anchor) {
    if (_menu.isOpen) return _menu.close();
    setState(() => _width = anchor.size!.width);
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13.5);
    final pick = widget.onChanged;
    final picked = widget.options.indexWhere((o) => o.value == widget.value);
    final shown =
        widget.selectedLabel ??
        (picked < 0 ? null : widget.options[picked].label);
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final (i, option) in widget.options.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 1),
            child: SizedBox(
              width: _width - 8,
              child: MenuItemButton(
                key: option.key,
                // keyboard focus lands on the pick, else on the first option
                autofocus: i == (picked < 0 ? 0 : picked),
                onPressed: pick == null || !option.enabled
                    ? null
                    : () => pick(option.value),
                style: i == picked
                    ? ButtonStyle(
                        foregroundColor: WidgetStatePropertyAll(
                          colors.accentText,
                        ),
                        textStyle: WidgetStatePropertyAll(
                          text.copyWith(fontWeight: FontWeight.w600),
                        ),
                      )
                    : null,
                leadingIcon: i == picked
                    ? Icon(UfIcons.check, size: 14, color: colors.accentText)
                    : const SizedBox(width: 14),
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: option.style,
                ),
              ),
            ),
          ),
      ],
      builder: (anchor, menu, _) => _Pressable(
        focusNode: _focus,
        onTap: pick == null ? null : () => _toggle(anchor),
        builder: (context, states) {
          final disabled = pick == null;
          final focused = states.contains(WidgetState.focused) || menu.isOpen;
          // every label stacked, so the box fits the widest one when its width is unbounded
          final labels = [
            for (final o in widget.options) (o.label, o.style),
            (
              shown ?? '',
              widget.selectedLabel == null && picked >= 0
                  ? widget.options[picked].style
                  : null,
            ),
          ];
          return Semantics(
            button: true,
            enabled: !disabled,
            value: shown,
            child: Container(
              height: UfHeight.medium,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: disabled ? colors.disabledBg : colors.field,
                borderRadius: UfRadius.control,
                border: Border.all(
                  color: disabled
                      ? colors.line
                      : focused
                      ? colors.focus
                      : states.contains(WidgetState.hovered)
                      ? colors.muted
                      : colors.edge,
                ),
                boxShadow: focused && !disabled
                    ? [BoxShadow(color: colors.focus, spreadRadius: 1)]
                    : null,
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  final value = IndexedStack(
                    index: labels.length - 1,
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      for (final (i, (label, style)) in labels.indexed)
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text
                              .copyWith(
                                color: disabled
                                    ? colors.disabledFg
                                    : i == labels.length - 1 && shown == null
                                    ? colors.muted
                                    : colors.text,
                              )
                              .merge(style),
                        ),
                    ],
                  );
                  return Row(
                    mainAxisSize: box.hasBoundedWidth
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    spacing: 8,
                    children: [
                      if (box.hasBoundedWidth)
                        Expanded(child: value)
                      else
                        value,
                      Icon(UfIcons.caretDown, size: 14, color: colors.muted),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// A 16 px radio: `field` with a 1 px `edge` ring at rest, `accent` with a 6 px `accentFg` dot when picked.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.states});

  final bool selected;
  final Set<WidgetState> states;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final fast = UfMotion.of(context).fast;
    final disabled = states.contains(WidgetState.disabled);
    final pressed = states.contains(WidgetState.pressed);
    final active = pressed || states.contains(WidgetState.hovered);
    return AnimatedContainer(
      duration: fast,
      curve: UfMotion.standard,
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: disabled
            ? colors.disabledBg
            : selected
            ? (pressed ? colors.accentPress : colors.accent)
            : (pressed ? colors.fieldPress : colors.field),
        border: disabled
            ? Border.all(color: colors.line)
            : selected
            ? null
            : Border.all(color: active ? colors.muted : colors.edge),
        boxShadow: states.contains(WidgetState.focused)
            ? UfElevation.focusRing(colors)
            : null,
      ),
      child: AnimatedOpacity(
        duration: fast,
        opacity: selected ? 1 : 0,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: disabled ? colors.disabledFg : colors.accentFg,
          ),
        ),
      ),
    );
  }
}

// Tracks hover, press and keyboard focus for the controls above; Enter and Space activate. Null onTap
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
