// SPDX-License-Identifier: Apache-2.0
part of 'choices.dart';

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
              child: _SelectOptionButton(
                option: option,
                isPicked: i == picked,
                // keyboard focus lands on the pick, else on the first option
                autofocus: i == (picked < 0 ? 0 : picked),
                onPressed: pick == null || !option.enabled
                    ? null
                    : () => pick(option.value),
                text: text,
              ),
            ),
          ),
      ],
      builder: (anchor, menu, _) => _Pressable(
        focusNode: _focus,
        onTap: pick == null ? null : () => _toggle(anchor),
        builder: (context, states) => _SelectBox(
          states: states,
          isOpen: menu.isOpen,
          shown: shown,
          // every label stacked, so the box fits the widest one when its width is unbounded
          labels: [
            for (final o in widget.options) (o.label, o.style),
            (
              shown ?? '',
              widget.selectedLabel == null && picked >= 0
                  ? widget.options[picked].style
                  : null,
            ),
          ],
          text: text,
        ),
      ),
    );
  }
}

class _SelectOptionButton<T> extends StatelessWidget {
  const _SelectOptionButton({
    required this.option,
    required this.isPicked,
    required this.autofocus,
    required this.onPressed,
    required this.text,
  });

  final UfOption<T> option;
  final bool isPicked;
  final bool autofocus;
  final VoidCallback? onPressed;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return MenuItemButton(
      key: option.key,
      autofocus: autofocus,
      onPressed: onPressed,
      style: isPicked
          ? ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(colors.accentText),
              textStyle: WidgetStatePropertyAll(
                text.copyWith(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      leadingIcon: isPicked
          ? Icon(UfIcons.check, size: 14, color: colors.accentText)
          : const SizedBox(width: 14),
      child: Text(
        option.label,
        overflow: TextOverflow.ellipsis,
        style: option.style,
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({
    required this.states,
    required this.isOpen,
    required this.shown,
    required this.labels,
    required this.text,
  });

  final Set<WidgetState> states;
  final bool isOpen;
  final String? shown;
  final List<(String, TextStyle?)> labels;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final disabled = states.contains(WidgetState.disabled);
    final focused = states.contains(WidgetState.focused) || isOpen;
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
            final value = _StackedLabels(
              labels: labels,
              isEmpty: shown == null,
              isDisabled: disabled,
              text: text,
            );
            return Row(
              mainAxisSize: box.hasBoundedWidth
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              spacing: 8,
              children: [
                if (box.hasBoundedWidth) Expanded(child: value) else value,
                Icon(UfIcons.caretDown, size: 14, color: colors.muted),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StackedLabels extends StatelessWidget {
  const _StackedLabels({
    required this.labels,
    required this.isEmpty,
    required this.isDisabled,
    required this.text,
  });

  final List<(String, TextStyle?)> labels;
  final bool isEmpty;
  final bool isDisabled;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return IndexedStack(
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
                  color: isDisabled
                      ? colors.disabledFg
                      : i == labels.length - 1 && isEmpty
                      ? colors.muted
                      : colors.text,
                )
                .merge(style),
          ),
      ],
    );
  }
}
