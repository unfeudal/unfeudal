// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'inputs.dart';
import 'tokens.dart';

/// One result of a [UfCommandPalette]: an optional 14 px [icon], the [label] with the query in bold, a [detail]
/// line, and a mono [hint] on the right ("Enter: connect").
class UfPaletteRow {
  const UfPaletteRow({
    required this.label,
    required this.onSelected,
    this.detail,
    this.hint,
    this.icon,
  });

  final String label;
  final VoidCallback onSelected;
  final String? detail;
  final String? hint;
  final Widget? icon;
}

/// A titled group of [UfPaletteRow]s ("Hosts · Acme Ops", "Snippets", "Actions").
class UfPaletteGroup {
  const UfPaletteGroup(this.title, this.rows);

  final String title;
  final List<UfPaletteRow> rows;
}

/// A focused search field over a menu-like result list, at most 560 wide. The caller filters [groups] on each
/// [onQueryChanged]; the palette only shows them. The arrows move the active row, Enter runs it, Escape clears
/// the query then calls [onDismiss].
class UfCommandPalette extends StatefulWidget {
  const UfCommandPalette({
    super.key,
    required this.groups,
    required this.onQueryChanged,
    required this.onDismiss,
    this.hint,
    this.focusNode,
  });

  final List<UfPaletteGroup> groups;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onDismiss;
  final String? hint;

  /// The search field's node, for a caller that opens the palette while something else holds focus.
  final FocusNode? focusNode;

  @override
  State<UfCommandPalette> createState() => _UfCommandPaletteState();
}

class _UfCommandPaletteState extends State<UfCommandPalette> {
  final _activeRow = GlobalKey();
  var _query = '';
  var _active = 0;

  List<UfPaletteRow> get _rows => [for (final g in widget.groups) ...g.rows];

  @override
  void didUpdateWidget(UfCommandPalette old) {
    super.didUpdateWidget(old);
    if (_active >= _rows.length) _active = 0;
  }

  void _typed(String query) {
    setState(() {
      _query = query;
      _active = 0;
    });
    widget.onQueryChanged(query);
  }

  void _move(int by) {
    final count = _rows.length;
    if (count == 0) return;
    setState(() => _active = (_active + by) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _activeRow.currentContext;
      if (row != null && row.mounted) Scrollable.ensureVisible(row);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        final rows = _rows;
        if (_active >= rows.length) return KeyEventResult.ignored;
        rows[_active].onSelected();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final showList = _rows.isNotEmpty || _query.isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: UfSearchField(
              focusNode: widget.focusNode,
              autofocus: true,
              hint: widget.hint,
              onChanged: _typed,
              onEscape: widget.onDismiss,
            ),
          ),
          if (showList)
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: UfRadius.card,
                boxShadow: UfElevation.floating(colors),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(4),
                child: _rows.isEmpty
                    ? Center(child: UfNoMatch(query: _query))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 1,
                        children: _list(colors),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _list(UfColors colors) {
    final text = Theme.of(context).textTheme;
    var index = 0;
    return [
      for (final group in widget.groups)
        if (group.rows.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              group.title,
              style: text.labelSmall!.copyWith(color: colors.muted),
            ),
          ),
          for (final row in group.rows) _row(colors, text, row, index++),
        ],
    ];
  }

  Widget _row(UfColors colors, TextTheme text, UfPaletteRow row, int index) {
    final active = index == _active;
    final hint = row.hint;
    final detail = row.detail;
    return Semantics(
      key: active ? _activeRow : null,
      button: true,
      selected: active,
      onTap: row.onSelected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _active = index),
        child: GestureDetector(
          onTap: row.onSelected,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: active ? colors.panelHover : null,
              borderRadius: UfRadius.control,
            ),
            child: Row(
              spacing: 10,
              children: [
                if (row.icon case final icon?)
                  IconTheme.merge(
                    data: IconThemeData(size: 14, color: colors.muted),
                    child: icon,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UfMatchText(
                        row.label,
                        query: _query,
                        style: text.bodyMedium!.copyWith(fontSize: 13.5),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall!.copyWith(color: colors.muted),
                        ),
                    ],
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      color: colors.muted,
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
