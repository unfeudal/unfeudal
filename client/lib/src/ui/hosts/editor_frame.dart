// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_state.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../vault/vault.dart';

/// A labelled dropdown of [entries] after a [none] item; a [value] not among them shows as [none].
Widget entryPicker({
  required String key,
  required String label,
  required String none,
  required List<VaultEntry> entries,
  required String? value,
  required ValueChanged<String?>? onChanged,
  String? source,
}) => UfField(
  label: label,
  source: source,
  child: DropdownButtonFormField<String?>(
    key: Key(key),
    initialValue: entries.any((e) => e.id == value) ? value : null,
    items: [
      DropdownMenuItem(key: Key('$key-root'), child: Text(none)),
      for (final e in entries)
        DropdownMenuItem(
          key: Key('$key-${e.id}'),
          value: e.id,
          child: Text(e.name ?? ''),
        ),
    ],
    onChanged: onChanged,
  ),
);

/// The vault an item lives in, for the inspector's breadcrumb.
String vaultNameOf(AppLocalizations l, AppState state, String? orgId) =>
    state.orgs?.orgs.where((o) => o.id == orgId).firstOrNull?.name ??
    l.vaultPersonal;

/// The inspector docked right of the sessions: where the item lives and its name, an optional connect
/// action, tabs when there are several, the fields, then trash on the left and Cancel / Save on the right.
/// Read-only items show [notice] and no footer.
class EditorFrame extends StatefulWidget {
  const EditorFrame({
    super.key,
    required this.title,
    this.crumb,
    this.notice,
    required this.children,
    this.tabs = const [],
    this.onClose,
    this.onConnect,
    this.save,
    this.trash,
  });

  static const width = 360.0;
  final String title;

  /// "Personnel / Maison".
  final String? crumb;
  final String? notice;

  /// The Connexion tab, or the only content.
  final List<Widget> children;

  /// Tabs after Connexion: each a label and its fields.
  final List<(String, List<Widget>)> tabs;
  final VoidCallback? onClose;
  final VoidCallback? onConnect;
  final Widget? save;
  final Widget? trash;

  @override
  State<EditorFrame> createState() => _EditorFrameState();
}

class _EditorFrameState extends State<EditorFrame> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final close = MaterialLocalizations.of(context);
    final tabs = [(l.inspectorTabConnection, widget.children), ...widget.tabs];
    final tab = _tab.clamp(0, tabs.length - 1);
    return Container(
      width: EditorFrame.width,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(left: BorderSide(color: colors.line)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        if (widget.crumb case final crumb?)
                          Text(
                            crumb,
                            style: text.bodySmall!.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                  if (widget.onConnect case final connect?)
                    FilledButton(
                      key: const Key('inspector-connect'),
                      style: smallButton,
                      onPressed: connect,
                      child: Text(l.inspectorConnect),
                    ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: close.closeButtonTooltip,
                      onPressed: widget.onClose,
                      icon: const Icon(UfIcons.x),
                    ),
                ],
              ),
            ),
            if (tabs.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.line)),
                ),
                child: Row(
                  spacing: 4,
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      _InspectorTab(
                        key: Key('inspector-tab-$i'),
                        label: tabs[i].$1,
                        selected: i == tab,
                        onTap: () => setState(() => _tab = i),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                children: [
                  if (widget.notice case final notice?)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warnSoft,
                        borderRadius: UfRadius.control,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Icon(UfIcons.warning, size: 16, color: colors.warn),
                          Expanded(child: Text(notice, style: text.bodySmall)),
                        ],
                      ),
                    ),
                  for (final child in tabs[tab].$2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: child,
                    ),
                ],
              ),
            ),
            if (widget.save != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.line)),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    if (widget.trash case final trash?)
                      TextButtonTheme(
                        data: TextButtonThemeData(
                          style: dangerQuietStyle(colors)
                              .merge(smallButton)
                              .merge(Theme.of(context).textButtonTheme.style),
                        ),
                        child: trash,
                      ),
                    const Spacer(),
                    if (widget.onClose != null)
                      CancelButton(onPressed: widget.onClose),
                    widget.save!,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `muted`, the selected one in `text` over a 2 px `accent` underline.
class _InspectorTab extends StatelessWidget {
  const _InspectorTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.transparent,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge!
                .copyWith(color: selected ? colors.text : colors.muted),
          ),
        ),
      ),
    );
  }
}
