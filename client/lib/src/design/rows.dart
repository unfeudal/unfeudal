// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// A group list left of a section's content: 30 px rows, the current one on `panelHover` in 600.
class GroupNav<T> extends StatelessWidget {
  const GroupNav({
    super.key,
    required this.groups,
    required this.current,
    required this.onPick,
  });

  final List<(T, String)> groups;
  final T current;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13.5);
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: [
          for (final (id, label) in groups)
            Semantics(
              selected: id == current,
              button: true,
              child: UfFocusRing(
                child: Material(
                  color: id == current ? colors.panelHover : Colors.transparent,
                  borderRadius: UfRadius.control,
                  child: InkWell(
                    key: Key('group-${id is Enum ? id.name : id}'),
                    borderRadius: UfRadius.control,
                    hoverColor: colors.panelHover,
                    hoverDuration: UfMotion.of(context).fast,
                    onTap: () => onPick(id),
                    child: Container(
                      height: 30,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        label,
                        style: id == current
                            ? text.copyWith(fontWeight: FontWeight.w600)
                            : text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One setting: its label and hint on the left, the control on the right, a `line` under it. [onTap] makes the
/// label a click target too, as for a switch.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.hint,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          spacing: 24,
          children: [
            Expanded(
              child: MouseRegion(
                cursor: onTap == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        label,
                        style: text.labelLarge!.copyWith(fontSize: 13.5),
                      ),
                      if (hint case final hint?)
                        Text(
                          hint,
                          style: text.bodySmall!.copyWith(color: colors.muted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A small `line`-edged badge: a folder tag, a role, a state written out.
class UfTag extends StatelessWidget {
  const UfTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        border: Border.all(color: colors.line),
        borderRadius: UfRadius.key,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(fontSize: 11, height: 16 / 11, color: colors.muted),
      ),
    );
  }
}

/// A list row: a 32 px icon tile, a title over a subtitle, then trailing badges and actions, a `line` under it.
class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing = const [],
    this.monoSubtitle = false,
    this.dimmed = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> trailing;
  final bool monoSubtitle;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final tile = icon == null
        ? null
        : Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.neutral,
              borderRadius: UfRadius.control,
            ),
            child: Icon(icon, size: 16, color: colors.text),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            spacing: 12,
            children: [
              ?tile,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge!.copyWith(
                        fontSize: 13.5,
                        color: dimmed ? colors.muted : colors.text,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoSubtitle
                            ? monoStyle.copyWith(
                                fontSize: 11,
                                color: colors.muted,
                              )
                            : text.bodySmall!.copyWith(color: colors.muted),
                      ),
                  ],
                ),
              ),
              // a narrow row wraps its actions onto a second line instead of overflowing
              if (trailing.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.65),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: trailing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum UfBadgeTone { accent, danger, neutral }

/// A count or a short state on a filled 18 px badge: `accent`, `danger` or `neutral`.
class UfBadge extends StatelessWidget {
  const UfBadge(this.label, {super.key, this.tone = UfBadgeTone.neutral});

  final String label;
  final UfBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final (fill, ink) = switch (tone) {
      UfBadgeTone.accent => (colors.accent, colors.accentFg),
      UfBadgeTone.danger => (colors.danger, colors.onDanger),
      UfBadgeTone.neutral => (colors.neutral, colors.text),
    };
    return Container(
      constraints: const BoxConstraints(
        minWidth: 18,
        minHeight: 18,
        maxHeight: 18,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, borderRadius: UfRadius.key),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall!
            .copyWith(fontSize: 11, height: 1, color: ink),
      ),
    );
  }
}

/// An inset 2 px `focus` ring over a row while a focusable inside it holds keyboard focus.
class UfFocusRing extends StatefulWidget {
  const UfFocusRing({
    super.key,
    required this.child,
    this.borderRadius = UfRadius.control,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<UfFocusRing> createState() => _UfFocusRingState();
}

class _UfFocusRingState extends State<UfFocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final keyboard =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      // always painted, so showing the ring never rebuilds the child
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: _focused && keyboard
              ? Border.all(color: UfColors.of(context).focus, width: 2)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// A 14 px spinner beside a `muted` label, while a list or a page loads.
class UfLoading extends StatelessWidget {
  const UfLoading(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(fontSize: 13, color: colors.muted),
        ),
      ],
    );
  }
}
