// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/api_client.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../debug_trace.dart';
import '../../design/banner.dart';
import '../../design/motion.dart';
import '../../ssh/connections.dart';
import '../../ssh/ssh_connector.dart';
import '../../storage/local_mirror.dart';
import '../../sync/sync_engine.dart';
import '../../version.dart';
import '../activity/activity_screen.dart';
import '../describe_error.dart';
import '../history/trash_screen.dart';
import '../hosts/folder_editor_panel.dart';
import '../hosts/host_editor_panel.dart';
import '../hosts/host_key_dialog.dart';
import '../keychain/keychain_screen.dart';
import '../orgs/members_section.dart';
import '../orgs/rotation_banner.dart';
import '../settings/settings_screen.dart';
import '../snippets/snippets_screen.dart';
import '../terminal/ssh_dialogs.dart';
import '../terminal/terminal_tabs.dart';
import 'shell_chrome.dart';
import 'shortcuts.dart';
import 'sidebar.dart';
import 'tree_panel.dart';

part 'shell_keys.dart';
part 'shell_sessions.dart';
part 'sidebar_resizer.dart';

/// Opens a link in the system browser; replaced in tests.
@visibleForTesting
Future<bool> Function(Uri url) openExternalUrl = launchUrl;

/// The sidebar (resizable, Ctrl+B hides it) beside the sessions under the status banners, or a section.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> implements SshDialogs {
  late final AppState _state = AppScope.read(context);
  final _searchFocus = FocusNode();
  final _terminalFocus = FocusNode();
  late double _treeWidth = _state.settings.treeWidth;
  bool _treeVisible = true;

  // The sidebar only: the terminal's keys never reach Loquet.
  final _loquetKeys = FocusNode(debugLabel: 'loquet-keys');
  bool _ledgerDismissed = false;

  // The host or folder inspector docked right of the sessions, if open.
  Widget? _editor;

  // The section in place of the sessions, if open.
  ShellPage? _page;

  // Kept to clear the title bar on dispose, when the context can no longer look it up.
  ShellChrome? _chrome;

  @override
  void initState() {
    super.initState();
    _state.connections.dialogs = this;
    _state.onHomeMounted();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _chrome = mounted ? ShellChromeScope.maybeOf(context) : null,
    );
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (identical(_state.connections.dialogs, this)) {
      _state.connections.dialogs = null;
    }
    _state.onHomeUnmounted();
    _searchFocus.dispose();
    _terminalFocus.dispose();
    _loquetKeys.dispose();
    // unmounting locks the tree: the title bar may rebuild only once this frame is done
    if (_chrome case final chrome?) {
      WidgetsBinding.instance.addPostFrameCallback((_) => chrome.clear(this));
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (_vaultShortcut(event, keyboard)) return true;
    final shortcut = UfShortcuts.resolve(
      event,
      ctrl: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
      inTerminal: _terminalFocus.hasFocus,
    );
    if (shortcut != null) trace(TraceArea.ui, 'shortcut ${shortcut.name}');
    switch (shortcut) {
      case UfShortcut.toggleTree:
        setState(() => _treeVisible = !_treeVisible);
      case UfShortcut.focusSearch || UfShortcut.newTab:
        _focusSearch();
      case UfShortcut.closeTab:
        if (_state.connections.activeSession case final tab?) {
          unawaited(_state.connections.closeTab(tab));
        }
      // handled by the focused terminal
      case UfShortcut.copy ||
          UfShortcut.paste ||
          UfShortcut.find ||
          UfShortcut.reconnect ||
          null:
        return false;
    }
    return true;
  }

  void _focusSearch() {
    setState(() {
      _page = null;
      _treeVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  @override
  Future<bool> confirmHostKey(HostKeyCheck check) async {
    if (!mounted) return false;
    final changed = check.decision == HostKeyDecision.changed;
    return await showUfDialog<bool>(
          context,
          (_) => changed
              ? HostKeyChangedDialog(check: check)
              : HostKeyUnknownDialog(check: check),
          alert: changed,
        ) ??
        false;
  }

  @override
  Future<bool> confirmStartupCommand(String hostName, String command) async {
    if (!mounted) return false;
    return await showUfDialog<bool>(
          context,
          (_) => StartupCommandDialog(hostName: hostName, command: command),
          alert: true,
        ) ??
        false;
  }

  @override
  Future<String?> askPassword(String target) async => mounted
      ? showUfDialog<String>(
          context,
          (_) => PasswordPromptDialog(target: target),
        )
      : null;

  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async => mounted
      ? showUfDialog<List<String>>(
          context,
          (_) => KeyboardInteractiveDialog(
            name: name,
            instruction: instruction,
            prompts: prompts,
          ),
        )
      : null;

  void _show(ShellPage? page) {
    trace(TraceArea.ui, 'page ${page?.name ?? 'vault'}');
    setState(() => _page = page);
  }

  void _editHost(String hostId) => _openEditor(
    (close) =>
        HostEditorPanel(key: ValueKey(hostId), hostId: hostId, onClose: close),
  );

  void _openEditor(Widget Function(VoidCallback close) build) {
    final editor = build(() {
      trace(TraceArea.ui, 'editor closed');
      setState(() => _editor = null);
    });
    trace(TraceArea.ui, 'editor open: ${editor.runtimeType}');
    setState(() => _editor = editor);
  }

  void _resize(double delta) => setState(
    () => _treeWidth = (_treeWidth + delta).clamp(_minTree, _maxTree),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final banners = _banners(context, state);
    final page = _page == ShellPage.members && selectedOrg(state) == null
        ? null
        : _page;
    void back() => _show(null);
    _publishChrome(context, state, page);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_treeVisible) ...[
            Focus(
              key: const Key('loquet-keys'),
              focusNode: _loquetKeys,
              onKeyEvent: (_, e) => _onLoquetKey(state, e),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _loquetKeys.requestFocus,
                child: AnimatedContainer(
                  key: const Key('tree-panel'),
                  duration: UfMotion.of(context).base,
                  curve: UfMotion.standard,
                  width: _treeWidth,
                  child: Sidebar(
                    tree: _treePanel(),
                    page: page,
                    onShow: _show,
                    onLock: state.lock,
                  ),
                ),
              ),
            ),
            _resizer(),
          ],
          Expanded(
            child: switch (page) {
              ShellPage.snippets => SnippetsScreen(onBack: back),
              ShellPage.keychain => KeychainScreen(onBack: back),
              ShellPage.members => MembersSection(
                orgId: state.orgs!.selected!,
                onBack: back,
              ),
              ShellPage.activity => ActivityScreen(onBack: back),
              ShellPage.trash => TrashScreen(onBack: back),
              ShellPage.settings => SettingsScreen(onBack: back),
              null => _Sessions(
                banners: banners,
                terminalFocus: _terminalFocus,
                onNewTab: _focusSearch,
                onEditHost: _editHost,
                editor: _editor,
              ),
            },
          ),
        ],
      ),
    );
  }

  // The title bar reads the sidebar width and the window title: the vault, then the section or session.
  void _publishChrome(BuildContext context, AppState state, ShellPage? page) {
    final chrome = ShellChromeScope.maybeOf(context);
    if (chrome == null) return;
    final l = AppLocalizations.of(context);
    final vault = selectedOrg(state)?.name ?? l.vaultPersonal;
    final tab = state.connections.activeSession?.title ?? l.statusNoSession;
    final title = switch (page) {
      ShellPage.settings => l.railSettings,
      final page? => '$vault \u2014 ${pageTitle(l, page)}',
      null => '$vault \u2014 $tab',
    };
    final width = _treeVisible ? _treeWidth : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      chrome.show(
        owner: this,
        sidebarWidth: width,
        title: title,
        toggleSidebar: () => setState(() => _treeVisible = !_treeVisible),
      );
    });
  }

  TreePanel _treePanel() => TreePanel(
    searchFocus: _searchFocus,
    onSettings: () => _show(ShellPage.settings),
    onNewHost: () => _openEditor(
      (close) => HostEditorPanel(orgId: _state.orgs?.selected, onClose: close),
    ),
    onNewFolder: () => _openEditor(
      (close) =>
          FolderEditorPanel(orgId: _state.orgs?.selected, onClose: close),
    ),
    onEdit: (e) => e.kind == ItemKind.folder
        ? _openEditor(
            (close) => FolderEditorPanel(
              key: ValueKey(e.id),
              folderId: e.id,
              onClose: close,
            ),
          )
        : _editHost(e.id),
  );

  // Top to bottom: plain http, restore, read-only, update, rejected writes, offline, protocol, key rotations,
  // ledger reset.
  List<Widget> _banners(BuildContext context, AppState state) {
    final l = AppLocalizations.of(context);
    final sync = state.sync;
    final download = (
      l.bannerDownload,
      () => unawaited(openExternalUrl(Uri.parse(officialReleasesUrl))),
    );
    return [
      if (state.stored?.serverUrl.scheme == 'http')
        StatusBanner(
          key: const Key('banner-plain-http'),
          tone: BannerTone.danger,
          message: l.bannerPlainHttp,
        ),
      if (sync != null && sync.restorePending)
        StatusBanner(
          tone: BannerTone.warn,
          message: sync.restoreRefused
              ? l.bannerRestoreRefused
              : l.bannerRestore,
          action: (l.restoreAccept, () => unawaited(sync.acceptRestore())),
          secondAction: sync.restoreRefused
              ? null
              : (l.restoreRefuse, () => unawaited(sync.refuseRestore())),
          actionKey: const Key('sync-restore-accept'),
          secondActionKey: const Key('sync-restore-refuse'),
        )
      else if (sync != null && sync.readOnly)
        StatusBanner(
          key: const Key('banner-read-only'),
          tone: BannerTone.danger,
          message: l.bannerReadOnly(_readOnlyReason(l, sync)),
          action: download,
          actionKey: const Key('update-download'),
        ),
      if (sync?.updateVersion case final version? when !(sync!.readOnly))
        StatusBanner(
          tone: BannerTone.info,
          message: l.bannerUpdate(version),
          action: download,
          actionKey: const Key('update-download'),
        ),
      if (sync != null)
        for (final entry in sync.rejected) _rejectedBanner(l, state, entry),
      if (sync != null && !sync.online)
        StatusBanner(tone: BannerTone.warn, message: l.bannerOffline),
      if (sync?.lastError is FormatException)
        StatusBanner(tone: BannerTone.warn, message: l.bannerProtocol),
      if (RotationBanner.shows(state)) const RotationBanner(),
      if (state.ledgerReported && !_ledgerDismissed)
        StatusBanner(
          tone: BannerTone.warn,
          message: l.bannerLedgerReset,
          onDismiss: () => setState(() => _ledgerDismissed = true),
        ),
    ];
  }
}
