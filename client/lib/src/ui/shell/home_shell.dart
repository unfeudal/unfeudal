// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../api/api_client.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/banner.dart';
import '../../debug_trace.dart';
import '../../design/motion.dart';
import '../../storage/local_mirror.dart';
import '../../sync/sync_engine.dart';
import '../../version.dart';
import '../admin/instance_admin_screen.dart';
import '../describe_error.dart';
import '../hosts/folder_editor_panel.dart';
import '../hosts/host_editor_panel.dart';
import '../../ssh/ssh_connector.dart';
import '../hosts/host_key_dialog.dart';
import '../devices/devices_screen.dart';
import '../keychain/keychain_screen.dart';
import '../orgs/rotation_banner.dart';
import '../settings/settings_screen.dart';
import '../terminal/ssh_dialogs.dart';
import '../terminal/terminal_tabs.dart';
import 'shortcuts.dart';
import 'tree_panel.dart';
import 'vault_rail.dart';

/// Opens a link in the system browser; replaced in tests.
@visibleForTesting
Future<bool> Function(Uri url) openExternalUrl = launchUrl;

/// Rail, resizable tree and terminal area, under the status banners.
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

  /// Rail and tree only: the terminal's keys never reach Loquet.
  final _loquetKeys = FocusNode(debugLabel: 'loquet-keys');
  bool _ledgerDismissed = false;

  /// The floating host or folder editor over the terminal, if open.
  Widget? _editor;

  /// The management screen in place of the tree and terminals, if open.
  ShellPage? _page;

  static const _minTree = 220.0, _maxTree = 400.0, _resizeStep = 16.0;

  @override
  void initState() {
    super.initState();
    _state
      ..dialogs = this
      ..onHomeMounted();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (identical(_state.dialogs, this)) _state.dialogs = null;
    _state.onHomeUnmounted();
    _searchFocus.dispose();
    _terminalFocus.dispose();
    _loquetKeys.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
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
        if (_state.tabs.isNotEmpty) {
          unawaited(_state.closeTab(_state.tabs[_state.activeTab]));
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

  void _saveWidth() => unawaited(
    _state.updateSettings(_state.settings.copyWith(treeWidth: _treeWidth)),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final banners = _banners(context, state);
    void back() => _show(null);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            key: const Key('loquet-keys'),
            focusNode: _loquetKeys,
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent) {
                state.loquet.show(state.loquet.engine.key(e.logicalKey));
              }
              // focused itself (a tap on the background), it keeps the arrows from moving the focus
              // away; a focused field or row inside still gets every key
              return _loquetKeys.hasPrimaryFocus
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _loquetKeys.requestFocus,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VaultRail(
                    page: _page,
                    onLock: state.lock,
                    onShow: _show,
                    showLoquet: _page != null || !_treeVisible,
                  ),
                  if (_page == null && _treeVisible) ...[
                    AnimatedContainer(
                      key: const Key('tree-panel'),
                      duration: UfMotion.of(context).base,
                      curve: UfMotion.curve,
                      width: _treeWidth,
                      child: _treePanel(),
                    ),
                    _resizer(),
                  ],
                ],
              ),
            ),
          ),
          if (_page case final page?)
            Expanded(
              child: switch (page) {
                ShellPage.keychain => KeychainScreen(onBack: back),
                ShellPage.devices => DevicesScreen(onBack: back),
                ShellPage.admin => InstanceAdminScreen(onBack: back),
                ShellPage.settings => SettingsScreen(onBack: back),
              },
            )
          else ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banners.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: banners,
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Focus(
                          focusNode: _terminalFocus,
                          child: TerminalTabs(
                            onNewTab: _focusSearch,
                            onShowTree: _treeVisible
                                ? null
                                : () => setState(() => _treeVisible = true),
                            onEditHost: _editHost,
                          ),
                        ),
                        if (_editor case final editor?)
                          Positioned(
                            top: 10,
                            right: 10,
                            bottom: 10,
                            child: editor,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _treePanel() => TreePanel(
    searchFocus: _searchFocus,
    onHide: () => setState(() => _treeVisible = false),
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

  Widget _resizer() => Focus(
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final step = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => -_resizeStep,
        LogicalKeyboardKey.arrowRight => _resizeStep,
        _ => null,
      };
      if (step == null) return KeyEventResult.ignored;
      _resize(step);
      _saveWidth();
      return KeyEventResult.handled;
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('tree-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _resize(d.delta.dx),
        onHorizontalDragEnd: (_) => _saveWidth(),
        child: const SizedBox(width: 6, height: double.infinity),
      ),
    ),
  );

  /// Top to bottom: plain http, restore, read-only, update, rejected writes, offline, protocol, key rotations,
  /// ledger reset.
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
      for (final entry in sync?.rejected ?? const <OutboxEntry>[])
        StatusBanner(
          tone: BannerTone.danger,
          message: l.bannerRejected(
            state.vault?.entry(entry.item.id)?.name ?? entry.item.type,
            describeError(l, ApiException(entry.lastError ?? 'internal', 0)),
          ),
          action: (
            l.rejectedRetry,
            () => unawaited(sync!.retry(entry.item.id)),
          ),
          secondAction: (
            l.rejectedKeep,
            () => unawaited(sync!.keepPersonalCopy(entry.item.id)),
          ),
          onDismiss: () => unawaited(sync!.discard(entry.item.id)),
          dismissTooltip: l.rejectedDiscard,
          actionKey: Key('unsynced-retry-${entry.item.id}'),
          secondActionKey: Key('unsynced-keep-${entry.item.id}'),
          dismissKey: Key('unsynced-discard-${entry.item.id}'),
        ),
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

  static String _readOnlyReason(AppLocalizations l, SyncEngine sync) =>
      switch (sync.compat?.reason) {
        'no-common-api' => l.readOnlyNoCommonApi,
        'client-too-old' => l.readOnlyClientTooOld,
        _ => l.bannerRestoreRefused,
      };
}
