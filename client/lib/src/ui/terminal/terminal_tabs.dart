// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/empty_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../shell/shortcuts.dart';
import 'forwards_badge.dart';
import 'terminal_pane.dart';

/// The tab strip, the terminals and the status bar; the active tab shares the terminal's background.
class TerminalTabs extends StatelessWidget {
  const TerminalTabs({super.key, this.onNewTab, this.onEditHost});

  /// Opens the search to pick a host (the same as Ctrl+Shift+T).
  final VoidCallback? onNewTab;
  final void Function(String hostId)? onEditHost;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final connections = state.connections;
    final colors = UfColors.of(context);
    if (connections.tabs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: EmptyState(title: l.tabsEmpty, body: l.tabsEmptyBody),
          ),
          const _StatusBar(),
        ],
      );
    }
    final active = connections.activeTab.clamp(0, connections.tabs.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(active: active, onNewTab: onNewTab),
        Expanded(
          child: ColoredBox(
            color: colors.term,
            child: IndexedStack(
              index: active,
              children: [
                for (final tab in connections.tabs)
                  TerminalPane(
                    key: ObjectKey(tab),
                    session: tab,
                    onEditHost: onEditHost,
                  ),
              ],
            ),
          ),
        ),
        const _StatusBar(),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.active, required this.onNewTab});

  final int active;
  final VoidCallback? onNewTab;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final connections = state.connections;
    final colors = UfColors.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.side,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              children: [
                for (var i = 0; i < connections.tabs.length; i++)
                  ListenableBuilder(
                    listenable: connections.tabs[i],
                    builder: (context, _) => _TabChip(
                      key: Key('tab-$i'),
                      index: i,
                      title: connections.tabs[i].title,
                      seal: connections.tabs[i].state,
                      selected: i == active,
                      onSelect: () => connections.selectTab(i),
                      onClose: () => connections.closeTab(connections.tabs[i]),
                      badge: ForwardsBadge(
                        tab: connections.tabs[i],
                        configured:
                            state.vault
                                ?.hostLookup(connections.tabs[i].hostId)
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
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: IconButton(
              key: const Key('tab-new'),
              tooltip: l.treeSearch(UfShortcuts.label(UfShortcut.newTab)),
              onPressed: onNewTab,
              icon: const Icon(UfIcons.plus),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
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
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  BoxDecoration _decoration(UfColors colors, BorderRadius top) {
    final selected = widget.selected;
    return BoxDecoration(
      color: selected
          ? colors.term
          : _hover
          ? colors.panelHover
          : Colors.transparent,
      borderRadius: top,
      border: selected
          ? Border(
              top: BorderSide(color: colors.line),
              left: BorderSide(color: colors.line),
              right: BorderSide(color: colors.line),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final selected = widget.selected;
    const top = BorderRadius.vertical(top: Radius.circular(6));
    final text = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      color: selected || _hover ? colors.text : colors.muted,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    // the active tab grows by the strip's bottom line so it joins the terminal
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: UfMotion.of(context).fast,
        curve: UfMotion.enter,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Transform.translate(
            offset: Offset(0, selected ? 1 : 0),
            child: Container(
              height: selected ? 33 : 32,
              decoration: _decoration(colors, top),
              child: Material(
                type: MaterialType.transparency,
                child: UfFocusRing(
                  borderRadius: top,
                  child: InkWell(
                    borderRadius: top,
                    hoverColor: Colors.transparent,
                    onTap: widget.onSelect,
                    child: _TabChipLabel(
                      index: widget.index,
                      title: widget.title,
                      seal: widget.seal,
                      style: text,
                      badge: widget.badge,
                      showClose: selected || _hover,
                      onClose: widget.onClose,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabChipLabel extends StatelessWidget {
  const _TabChipLabel({
    required this.index,
    required this.title,
    required this.seal,
    required this.style,
    required this.badge,
    required this.showClose,
    required this.onClose,
  });

  final int index;
  final String title;
  final SealState seal;
  final TextStyle style;
  final Widget badge;
  final bool showClose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Seal(state: seal, size: 12),
          Text(title, style: style),
          badge,
          Opacity(
            opacity: showClose ? 0.75 : 0,
            child: IconButton(
              key: Key('tab-close-$index'),
              tooltip: AppLocalizations.of(context).tabClose,
              iconSize: 12,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(16),
                minimumSize: const Size.square(16),
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(borderRadius: UfRadius.key),
              ),
              onPressed: onClose,
              icon: const Icon(UfIcons.x),
            ),
          ),
        ],
      ),
    );
  }
}

// Under the terminal: the active target (and its jump host), its running forwards, then the sync state.
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    final tab = state.connections.activeSession;
    final forwards = tab?.forwarder;
    return Container(
      key: const Key('status-bar'),
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.side,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        spacing: 16,
        children: [
          Flexible(
            child: Text(
              tab == null ? l.statusNoSession : _target(l, state, tab.hostId),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (forwards != null)
            ListenableBuilder(
              listenable: forwards,
              builder: (context, _) => forwards.active.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      l.statusForwards(forwards.active.length),
                      style: style,
                    ),
            ),
          const Spacer(),
          ..._sync(l, state, style),
        ],
      ),
    );
  }

  // user@address[:port], followed by "via" and the jump host's name when there is one.
  static String _target(AppLocalizations l, AppState state, String hostId) {
    final lookup = state.vault?.hostLookup(hostId);
    if (lookup == null) return '';
    final (:meta, :resolved, org: _) = lookup;
    final target = [
      if (resolved.user case final user?) '$user@',
      meta.address,
      if (resolved.port != 22) ':${resolved.port}',
    ].join();
    final jump = switch (resolved.jumpHostId) {
      final id? => state.vault?.entry(id)?.name,
      null => null,
    };
    return jump == null ? target : l.statusVia(target, jump);
  }

  static List<Widget> _sync(
    AppLocalizations l,
    AppState state,
    TextStyle style,
  ) {
    final sync = state.sync;
    if (sync == null) return const [];
    final (seal, label) = !sync.online
        ? (SealState.offline, l.sealOffline)
        : sync.lastSyncAt == null
        ? (SealState.verify, l.statusSyncing)
        : (SealState.connected, l.statusSynced);
    return [
      Row(
        spacing: 6,
        children: [
          Seal(state: seal, size: 12),
          Text(label, style: style),
        ],
      ),
    ];
  }
}
