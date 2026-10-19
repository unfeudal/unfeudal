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
    state.orgs?.byId(orgId)?.name ?? l.vaultPersonal;

/// The inspector docked right of the sessions: where the item lives and its name, an optional connect
/// action, tabs when there are several, the fields, then trash on the left and Cancel / Save on the right.
/// Read-only items show [notice] and no footer.
class EditorFrame extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final close = MaterialLocalizations.of(context);
    final tabs = [(l.inspectorTabConnection, children), ...this.tabs];
    return Container(
      width: EditorFrame.width,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(left: BorderSide(color: colors.line)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTabController(
          length: tabs.length,
          animationDuration: Duration.zero,
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
                          if (crumb case final crumb?)
                            Text(
                              crumb,
                              style: text.bodySmall!.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    if (onConnect case final connect?)
                      FilledButton(
                        key: const Key('inspector-connect'),
                        style: smallButton,
                        onPressed: connect,
                        child: Text(l.inspectorConnect),
                      ),
                    if (onClose != null)
                      IconButton(
                        tooltip: close.closeButtonTooltip,
                        onPressed: onClose,
                        icon: const Icon(UfIcons.x),
                      ),
                  ],
                ),
              ),
              if (tabs.length > 1)
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    for (var i = 0; i < tabs.length; i++)
                      Tab(
                        key: Key('inspector-tab-$i'),
                        height: 32,
                        text: tabs[i].$1,
                      ),
                  ],
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final controller = DefaultTabController.of(context);
                    return ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        children: [
                          if (notice case final notice?)
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
                                  Icon(
                                    UfIcons.warning,
                                    size: 16,
                                    color: colors.warn,
                                  ),
                                  Expanded(
                                    child: Text(notice, style: text.bodySmall),
                                  ),
                                ],
                              ),
                            ),
                          for (final child in tabs[controller.index].$2)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: child,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (save != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.line)),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      if (trash case final trash?)
                        TextButtonTheme(
                          data: TextButtonThemeData(
                            style: dangerQuietStyle(colors)
                                .merge(smallButton)
                                .merge(Theme.of(context).textButtonTheme.style),
                          ),
                          child: trash,
                        ),
                      const Spacer(),
                      if (onClose != null) CancelButton(onPressed: onClose),
                      save!,
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
