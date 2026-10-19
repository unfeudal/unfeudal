// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/empty_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../shell/shortcuts.dart';
import 'forwards_badge.dart';
import 'terminal_pane.dart';

/// The tab strip over the terminals; the active tab shares the terminal's background.
class TerminalTabs extends StatelessWidget {
  const TerminalTabs({
    super.key,
    this.onNewTab,
    this.onShowTree,
    this.onEditHost,
  });

  /// Opens the search to pick a host (the same as Ctrl+Shift+T).
  final VoidCallback? onNewTab;

  /// Set while the tree is hidden: the strip then starts with the button that shows it.
  final VoidCallback? onShowTree;
  final void Function(String hostId)? onEditHost;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final showTree = onShowTree == null
        ? null
        : IconButton(
            key: const Key('tree-show'),
            tooltip: l.treeShow,
            iconSize: 17,
            onPressed: onShowTree,
            icon: const Icon(UfIcons.sidebarSimple),
          );
    if (state.tabs.isEmpty) {
      return Stack(
        children: [
          EmptyState(title: l.tabsEmpty, body: l.tabsEmptyBody),
          if (showTree != null) Positioned(top: 8, left: 10, child: showTree),
        ],
      );
    }
    final active = state.activeTab.clamp(0, state.tabs.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.bg,
          height: 46,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              ?showTree,
              Flexible(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < state.tabs.length; i++)
                      ListenableBuilder(
                        listenable: state.tabs[i],
                        builder: (context, _) => _TabChip(
                          key: Key('tab-$i'),
                          index: i,
                          title: state.tabs[i].title,
                          seal: state.tabs[i].state,
                          selected: i == active,
                          onSelect: () => state.selectTab(i),
                          onClose: () => state.closeTab(state.tabs[i]),
                          badge: ForwardsBadge(
                            tab: state.tabs[i],
                            configured:
                                state.vault
                                    ?.hostLookup(state.tabs[i].hostId)
                                    ?.meta
                                    .forwards ??
                                const [],
                            index: i,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: IconButton(
                  key: const Key('tab-new'),
                  tooltip: l.treeSearch(UfShortcuts.label(UfShortcut.newTab)),
                  iconSize: 15,
                  onPressed: onNewTab,
                  icon: const Icon(UfIcons.plus),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: colors.term,
            child: IndexedStack(
              index: active,
              children: [
                for (final tab in state.tabs)
                  TerminalPane(
                    key: ObjectKey(tab),
                    session: tab,
                    onEditHost: onEditHost,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.index,
    required this.title,
    required this.seal,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.badge,
  });

  final int index;
  final String title;
  final SealState seal;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: UfMotion.of(context).fast,
        curve: UfMotion.curve,
        builder: (context, t, child) =>
            Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
        child: Material(
          color: selected ? colors.term : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          child: InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Seal(state: seal, size: 13),
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? colors.text : colors.muted,
                    ),
                  ),
                  badge,
                  IconButton(
                    key: Key('tab-close-$index'),
                    tooltip: AppLocalizations.of(context).tabClose,
                    iconSize: 12,
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(UfIcons.x),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
