// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/empty_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import 'terminal_pane.dart';

/// The tab strip (seal + title) over the terminals; an empty state when no session is open.
class TerminalTabs extends StatelessWidget {
  const TerminalTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    if (state.tabs.isEmpty) {
      return EmptyState(title: l.tabsEmpty, body: l.tabsEmptyBody);
    }
    final active = state.activeTab.clamp(0, state.tabs.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.side,
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
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
                    closeTooltip: l.tabClose,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: active,
            children: [
              for (final tab in state.tabs)
                TerminalPane(key: ObjectKey(tab), session: tab),
            ],
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
    required this.closeTooltip,
  });

  final int index;
  final String title;
  final SealState seal;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: UfMotion.of(context).fast,
      curve: UfMotion.curve,
      builder: (context, t, child) =>
          Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      child: Material(
        color: selected ? colors.bg : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Seal(state: seal),
                Text(title),
                IconButton(
                  key: Key('tab-close-$index'),
                  tooltip: closeTooltip,
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(UfIcons.x),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
