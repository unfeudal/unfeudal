// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'tokens.dart';

/// A group list left of a section's content: 32 px rows, the current one on `panelHover` in 600.
class GroupNav<T> extends StatelessWidget {
  const GroupNav({
    super.key,
    required this.groups,
    required this.current,
    required this.onPick,
    this.width = 180,
  });

  final List<(T, String)> groups;
  final T current;
  final ValueChanged<T> onPick;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13.5);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: [
          for (final (id, label) in groups)
            Semantics(
              selected: id == current,
              button: true,
              child: Material(
                color: id == current ? colors.panelHover : Colors.transparent,
                borderRadius: UfRadius.control,
                child: InkWell(
                  key: Key('group-${id is Enum ? id.name : id}'),
                  borderRadius: UfRadius.control,
                  hoverColor: colors.panelHover,
                  onTap: () => onPick(id),
                  child: Container(
                    height: UfHeight.medium,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
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
        ],
      ),
    );
  }
}

/// One setting: its label and hint on the left, the control on the right, a `line` under it.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.label, this.hint, this.trailing});

  final String label;
  final String? hint;
  final Widget? trailing;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(label, style: text.labelLarge!.copyWith(fontSize: 13.5)),
                  if (hint case final hint?)
                    Text(
                      hint,
                      style: text.bodySmall!.copyWith(color: colors.muted),
                    ),
                ],
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
  const UfTag(this.label, {super.key, this.color});

  final String label;

  /// The text colour; `muted` by default.
  final Color? color;

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
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          fontSize: 11,
          height: 16 / 11,
          color: color ?? colors.muted,
        ),
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
    this.leading,
    this.trailing = const [],
    this.monoSubtitle = false,
    this.dimmed = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Replaces the icon tile (an avatar letter, a seal).
  final Widget? leading;
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
        child: Row(
          spacing: 12,
          children: [
            ?(leading ?? tile),
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
            ...trailing,
          ],
        ),
      ),
    );
  }
}
