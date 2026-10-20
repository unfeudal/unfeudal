// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'tokens.dart';

enum UfTriState { allow, deny, unset }

/// One right for one principal, 28 px: "Allow" on `okSoft`, "Deny" on `dangerSoft`, or a muted "—" in a `line`
/// edge when unset. A click cycles allow → deny → unset; without [canDeny] it cycles allow → unset. Null
/// [onChanged] disables it. [semanticLabel] (the right's name) is read before the state.
class UfTriToggle extends StatelessWidget {
  const UfTriToggle({
    super.key,
    required this.state,
    required this.onChanged,
    this.canDeny = true,
    this.semanticLabel,
  });

  final UfTriState state;
  final ValueChanged<UfTriState>? onChanged;
  final bool canDeny;
  final String? semanticLabel;

  UfTriState get _next => switch (state) {
    UfTriState.allow => canDeny ? UfTriState.deny : UfTriState.unset,
    UfTriState.deny => UfTriState.unset,
    UfTriState.unset => UfTriState.allow,
  };

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final l = AppLocalizations.of(context);
    final (fill, ink, word) = switch (state) {
      UfTriState.allow => (colors.okSoft, colors.ok, l.aclAllow),
      UfTriState.deny => (colors.dangerSoft, colors.danger, l.aclDeny),
      UfTriState.unset => (Colors.transparent, colors.muted, l.aclUnset),
    };
    final change = onChanged;
    return TextButton(
      onPressed: change == null ? null : () => change(_next),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty<Color>.fromMap({
          WidgetState.disabled: state == UfTriState.unset
              ? Colors.transparent
              : colors.disabledBg,
          WidgetState.any: fill,
        }),
        foregroundColor: WidgetStateProperty<Color>.fromMap({
          WidgetState.disabled: colors.disabledFg,
          WidgetState.any: ink,
        }),
        minimumSize: const WidgetStatePropertyAll(Size(76, UfHeight.small)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
        side: WidgetStateBorderSide.fromMap({
          WidgetState.focused: BorderSide(
            color: colors.focus,
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          WidgetState.any: state == UfTriState.unset
              ? BorderSide(color: colors.line)
              : BorderSide.none,
        }),
      ),
      child: Text(
        state == UfTriState.unset ? '—' : word,
        semanticsLabel: [?semanticLabel, word].join(', '),
      ),
    );
  }
}

/// Rights against principals: [headers] name the principal column then one column per right, 12/600 muted
/// and centred; each of [rows] holds the principal then one cell per right, centred, with a `line` rule under.
class UfAclGrid extends StatelessWidget {
  const UfAclGrid({super.key, required this.headers, required this.rows});

  final List<String> headers;
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final rule = BoxDecoration(
      border: Border(bottom: BorderSide(color: colors.line)),
    );
    Widget cell(int column, Widget child) => Padding(
      padding: column == 0
          ? const EdgeInsets.fromLTRB(0, 6, 8, 6)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: column == 0
          ? Align(alignment: AlignmentDirectional.centerStart, child: child)
          : Center(child: child),
    );
    return Table(
      columnWidths: const {0: FlexColumnWidth()},
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: rule,
          children: [
            for (final (i, header) in headers.indexed)
              cell(
                i,
                Text(
                  header,
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: colors.muted),
                ),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            decoration: rule,
            children: [
              for (final (i, child) in row.indexed)
                cell(
                  i,
                  i == 0
                      ? DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 13),
                          child: child,
                        )
                      : child,
                ),
            ],
          ),
      ],
    );
  }
}
