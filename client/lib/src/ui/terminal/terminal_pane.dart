// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/icons.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';
import '../../ssh/ssh_connector.dart';
import '../../terminal/charte_theme.dart';
import '../../terminal/snippet_insertion.dart';
import '../../terminal/terminal_search.dart';
import '../../terminal/terminal_session.dart';
import '../describe_error.dart';
import '../shell/shortcuts.dart';
import 'multiline_dialog.dart';

part 'error_card.dart';

/// One tab's terminal: copy, paste, scrollback search, a context menu and reconnect after a hang-up.
/// Plain Ctrl keys reach the shell; the terminal shortcuts need Ctrl+Shift (Cmd on macOS).
class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session, this.onEditHost});

  final TerminalSession session;
  final void Function(String hostId)? onEditHost;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _scroll = ScrollController();
  final _view = GlobalKey<TerminalViewState>();
  final _query = TextEditingController();
  final _searchFocus = FocusNode();
  final _contextMenu = MenuController();
  bool _searching = false;
  List<TerminalMatch> _hits = const [];
  int _current = 0;
  final _highlights = <TerminalHighlight>[];

  TerminalSession get _session => widget.session;

  @override
  void dispose() {
    _clearHighlights();
    _scroll.dispose();
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final shortcut = UfShortcuts.resolve(
      event,
      ctrl: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
      inTerminal: true,
    );
    switch (shortcut) {
      case UfShortcut.copy:
        _copy();
      case UfShortcut.paste:
        unawaited(_paste());
      case UfShortcut.find:
        _openSearch();
      case UfShortcut.reconnect
          when _session.state != SealState.connected &&
              _session.state != SealState.connecting:
        unawaited(_reconnect());
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _copy() {
    final selection = _session.controller.selection;
    if (selection == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(text: _session.terminal.buffer.getText(selection)),
      ),
    );
    _session.controller.clearSelection();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || !mounted) return;
    await insertSnippet(
      _session,
      text,
      confirm: () => confirmUnsafeMultiline(context),
    );
  }

  Future<void> _reconnect() =>
      AppScope.read(context).connections.reconnect(_session);

  void _openMenu(TapDownDetails details, CellOffset _) {
    // The items' enabled state follows the selection.
    setState(() {});
    _contextMenu.open(position: details.localPosition);
  }

  List<Widget> _menuItems(AppLocalizations l) {
    final colors = UfColors.of(context);
    Widget item({
      required String key,
      required String label,
      required UfShortcut shortcut,
      required VoidCallback? onPressed,
    }) => MenuItemButton(
      key: Key(key),
      onPressed: onPressed,
      trailingIcon: Text(
        UfShortcuts.label(shortcut),
        style: monoStyle.copyWith(fontSize: 11, color: colors.muted),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Text(label),
      ),
    );
    return [
      item(
        key: 'term-menu-copy',
        label: l.termCopy,
        shortcut: UfShortcut.copy,
        onPressed: _session.controller.selection == null ? null : _copy,
      ),
      item(
        key: 'term-menu-paste',
        label: l.termPaste,
        shortcut: UfShortcut.paste,
        onPressed: _session.state == SealState.connected
            ? () => unawaited(_paste())
            : null,
      ),
      item(
        key: 'term-menu-search',
        label: l.termSearch,
        shortcut: UfShortcut.find,
        onPressed: _openSearch,
      ),
    ];
  }

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _clearHighlights();
    setState(() {
      _searching = false;
      _hits = const [];
      _query.clear();
    });
  }

  void _clearHighlights() {
    for (final h in _highlights) {
      h.dispose();
    }
    _highlights.clear();
  }

  void _search(String query) {
    _hits = findInTerminal(_session.terminal, query);
    // The latest output comes first.
    _current = _hits.length - 1;
    _paint();
  }

  void _step(int by) {
    if (_hits.isEmpty) return;
    _current = (_current + by) % _hits.length;
    _paint();
  }

  void _paint() {
    final colors = UfColors.of(context);
    final buffer = _session.terminal.buffer;
    _clearHighlights();
    for (final (i, m) in _hits.indexed) {
      _highlights.add(
        _session.controller.highlight(
          p1: buffer.createAnchor(m.x, m.y),
          p2: buffer.createAnchor(m.x + m.length, m.y),
          color: i == _current ? colors.accent : colors.select,
        ),
      );
    }
    if (_hits.isNotEmpty && _scroll.hasClients) {
      final line = _view.currentState!.renderTerminal.lineHeight;
      final position = _scroll.position;
      _scroll.jumpTo(
        (_hits[_current].y * line - position.viewportDimension / 2).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        if (_session.error case final error?) {
          return _ErrorCard(
            session: _session,
            error: error,
            onEditHost: widget.onEditHost,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_session.state == SealState.offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: StatusBanner(
                  tone: BannerTone.info,
                  message: l.termClosed,
                  action: (l.termReconnect, () => unawaited(_reconnect())),
                  actionKey: const Key('term-reconnect'),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  MenuAnchor(
                    controller: _contextMenu,
                    menuChildren: _menuItems(l),
                    child: TerminalView(
                      _session.terminal,
                      key: _view,
                      controller: _session.controller,
                      scrollController: _scroll,
                      autofocus: true,
                      // Empty, to drop xterm2's own Ctrl+C/V.
                      shortcuts: const {},
                      onKeyEvent: _onKey,
                      onSecondaryTapDown: _openMenu,
                      theme: terminalThemeFor(
                        settings.terminalTheme,
                        Theme.of(context).brightness,
                      ),
                      textStyle: TerminalStyle(
                        fontFamily: settings.terminalFont,
                        fontSize: settings.terminalFontSize.toDouble(),
                      ),
                    ),
                  ),
                  if (_searching)
                    Positioned(top: 8, right: 8, child: _searchBar(l)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _searchBar(AppLocalizations l) {
    final colors = UfColors.of(context);
    final status = _query.text.isEmpty
        ? ''
        : _hits.isEmpty
        ? l.termSearchNone
        : l.termSearchCount(_current + 1, _hits.length);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
      },
      child: Material(
        color: colors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: UfRadius.card,
          side: BorderSide(color: colors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  key: const Key('term-search-input'),
                  controller: _query,
                  focusNode: _searchFocus,
                  onChanged: _search,
                  onSubmitted: (_) {
                    _step(1);
                    _searchFocus.requestFocus();
                  },
                  decoration: InputDecoration(hintText: l.termSearch),
                ),
              ),
              Text(status, style: TextStyle(color: colors.muted)),
              IconButton(
                key: const Key('term-search-prev'),
                tooltip: l.termSearchPrev,
                onPressed: () => _step(-1),
                icon: const Icon(UfIcons.caretLeft),
              ),
              IconButton(
                key: const Key('term-search-next'),
                tooltip: l.termSearchNext,
                onPressed: () => _step(1),
                icon: const Icon(UfIcons.caretRight),
              ),
              IconButton(
                key: const Key('term-search-close'),
                tooltip: l.termSearchClose,
                onPressed: _closeSearch,
                icon: const Icon(UfIcons.x),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
