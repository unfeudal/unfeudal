// SPDX-License-Identifier: Apache-2.0
part of 'choices.dart';

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
    final selected = value == groupValue;
    return _RadioPressable<T>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
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
                  color: onChanged == null ? colors.disabledFg : colors.text,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RadioPressable<T> extends StatelessWidget {
  const _RadioPressable({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.builder,
  });

  final T value;
  final T groupValue;
  final ValueChanged<T>? onChanged;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;

  @override
  Widget build(BuildContext context) {
    final pick = onChanged;
    return MergeSemantics(
      child: Semantics(
        checked: value == groupValue,
        inMutuallyExclusiveGroup: true,
        enabled: pick != null,
        child: _Pressable(
          onTap: pick == null ? null : () => pick(value),
          builder: builder,
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
    final selected = value == groupValue;
    return _RadioPressable<T>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
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
