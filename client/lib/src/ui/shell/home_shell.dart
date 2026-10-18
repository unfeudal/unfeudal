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
import '../../design/motion.dart';
import '../../storage/local_mirror.dart';
import '../../sync/sync_engine.dart';
import '../../version.dart';
import '../describe_error.dart';
import '../hosts/folder_editor_panel.dart';
import '../hosts/host_editor_panel.dart';
import '../../ssh/ssh_connector.dart';
import '../hosts/host_key_dialog.dart';
import '../devices/devices_screen.dart';
import '../keychain/keychain_screen.dart';
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
  bool _ledgerDismissed = false;

  /// The floating host or folder editor over the terminal, if open.
  Widget? _editor;

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
    switch (shortcut) {
      case UfShortcut.toggleTree:
        setState(() => _treeVisible = !_treeVisible);
      case UfShortcut.focusSearch || UfShortcut.newTab:
        setState(() => _treeVisible = true);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _searchFocus.requestFocus(),
        );
      case UfShortcut.closeTab:
        if (_state.tabs.isNotEmpty) {
          unawaited(_state.closeTab(_state.tabs[_state.activeTab]));
        }
      case null:
        return false;
    }
    return true;
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

  void _push(Widget screen) => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );

  void _openEditor(Widget Function(VoidCallback close) build) =>
      setState(() => _editor = build(() => setState(() => _editor = null)));

  void _resize(double delta) => setState(
    () => _treeWidth = (_treeWidth + delta).clamp(_minTree, _maxTree),
  );

  void _saveWidth() => unawaited(
    _state.updateSettings(_state.settings.copyWith(treeWidth: _treeWidth)),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: Row(
        children: [
          VaultRail(
            onLock: state.lock,
            onKeychain: () => _push(const KeychainScreen()),
            onDevices: () => _push(const DevicesScreen()),
            onSettings: () => _push(const SettingsScreen()),
          ),
          if (_treeVisible) ...[
            AnimatedContainer(
              key: const Key('tree-panel'),
              duration: UfMotion.of(context).base,
              curve: UfMotion.curve,
              width: _treeWidth,
              child: TreePanel(
                searchFocus: _searchFocus,
                onNewHost: () =>
                    _openEditor((close) => HostEditorPanel(onClose: close)),
                onNewFolder: () =>
                    _openEditor((close) => FolderEditorPanel(onClose: close)),
                onEdit: (e) => _openEditor(
                  (close) => e.kind == ItemKind.folder
                      ? FolderEditorPanel(
                          key: ValueKey(e.id),
                          folderId: e.id,
                          onClose: close,
                        )
                      : HostEditorPanel(
                          key: ValueKey(e.id),
                          hostId: e.id,
                          onClose: close,
                        ),
                ),
              ),
            ),
            _resizer(),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._banners(context, state),
                Expanded(
                  child: Stack(
                    children: [
                      Focus(
                        focusNode: _terminalFocus,
                        child: const TerminalTabs(),
                      ),
                      if (_editor case final editor?)
                        Positioned(
                          top: 12,
                          right: 12,
                          bottom: 12,
                          child: editor,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  /// Top to bottom: plain http, restore, read-only, update, rejected writes, offline, protocol, ledger reset.
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
      if (sync?.updateNotice case final notice? when !(sync!.readOnly))
        StatusBanner(
          tone: BannerTone.info,
          message: l.bannerUpdate(notice.version),
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
