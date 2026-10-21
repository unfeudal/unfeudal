// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../debug_trace.dart';
import '../design/seal.dart';
import '../events/app_events.dart';
import '../loquet/reaction_engine.dart';
import '../orgs/host_binding.dart';
import '../sync/ledger_store.dart';
import '../terminal/terminal_session.dart';
import '../vault/vault.dart';
import 'jump_connector.dart';
import 'port_forwarder.dart';
import 'ssh_connector.dart';

/// The UI the SSH connection needs: host-key decisions, startup commands, passwords and prompts.
abstract interface class SshDialogs {
  Future<bool> confirmHostKey(HostKeyCheck check);
  Future<bool> confirmStartupCommand(String hostName, String command);
  Future<String?> askPassword(String target);
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  );
}

/// The startup command sent with the shell. An org host's command can be written by anyone with `edit`:
/// it runs only once the user approved this exact text on this device (SHA-256 in the sealed ledger).
Future<String?> startupCommandToSend({
  required String hostId,
  required String hostName,
  required String? command,
  required bool org,
  required LedgerStore ledger,
  required SshDialogs? dialogs,
}) async {
  if (command == null || !org) return command;
  final hash = await startupCommandHash(command);
  if (ledger.startupApproval(hostId) == hash) return command;
  if (await dialogs?.confirmStartupCommand(hostName, command) != true) {
    // The session opens without it.
    return null;
  }
  await ledger.approveStartup(hostId, hash);
  return command;
}

/// The terminal tabs: their SSH connections through jump hosts, port forwards and host-key decisions.
class Connections implements SshCallbacks {
  Connections({
    required this._ssh,
    required this._vault,
    required this._emit,
    required this._loquet,
    required this._changed,
  });

  final SshConnector _ssh;
  // The vault is replaced at each unlock.
  final Vault? Function() _vault;
  final void Function(AppEvent) _emit;
  final ReactionEngine _loquet;
  final void Function() _changed;

  final tabs = <TerminalSession>[];
  int activeTab = 0;
  SshDialogs? dialogs;

  // Tabs whose shell opened: each leaves once, with a SessionClosed.
  final _live = <TerminalSession>{};

  /// The tab shown; null without tabs.
  TerminalSession? get activeSession =>
      tabs.isEmpty ? null : tabs[activeTab.clamp(0, tabs.length - 1)];

  Vault get _openVault => _vault()!;

  // Null for a missing, trashed or unreadable host: the chain reports JumpHostMissing.
  ResolvedHost? _jumpLookup(String id) =>
      _openVault.isTrashed(id) ? null : _openVault.hostLookup(id)?.resolved;

  Future<ConnectTarget> _targetFor(String id) async {
    final vault = _openVault;
    final found = vault.hostLookup(id)!;
    final user = found.resolved.user ?? (throw const MissingUser());
    final entry = vault.entry(id)!;
    // A per-member org host uses the member's own binding: never inherited, never the org's.
    final identityId =
        found.meta.identityMode == IdentityMode.perMember && entry.orgId != null
        ? bindingFor(vault, id) ?? (throw MissingBinding(id))
        : found.resolved.identityId;
    return ConnectTarget(
      hostId: id,
      hostName: found.meta.name,
      address: found.meta.address,
      port: found.resolved.port,
      user: user,
      identity: identityId == null
          ? null
          : await vault.identitySecret(identityId),
    );
  }

  /// Failures stay in the tab (seal and message), never thrown to the UI.
  Future<TerminalSession> connect(String hostId) async {
    final found =
        _openVault.hostLookup(hostId) ?? (throw StateError('unknown host'));
    final tab = TerminalSession(hostId: hostId, title: found.meta.name);
    final input = tab.onUserInput;
    // only that a key was typed, never which
    tab.onUserInput = () {
      input?.call();
      _loquet.noteTerminalInput();
    };
    tabs.add(tab);
    activeTab = tabs.length - 1;
    _changed();
    _emit(ConnectStarted(hostId: hostId));
    try {
      final (:hopIds, :target, :conn) = await _openChain(hostId);
      tab.connection = conn;
      tab.attach(
        await conn.target.shell(),
        startupCommand: await startupCommandToSend(
          hostId: hostId,
          hostName: found.meta.name,
          command: found.meta.startupCommand,
          org: found.isOrg,
          ledger: _openVault.ledger,
          dialogs: dialogs,
        ),
      );
      if (hopIds.isNotEmpty) _emit(JumpUsed(hostId: hostId, hopIds: hopIds));
      _live.add(tab);
      tab.addListener(() {
        // the host ended the shell
        if (tab.state == SealState.offline) _sessionClosed(tab);
      });
      _emit(
        ConnectSucceeded(
          hostId: hostId,
          user: target.user,
          tags: found.meta.tags,
        ),
      );
      tab.forwarder = PortForwarder(conn.target.forwardLocal);
      await _startAutoForwards(tab, found.meta.forwards);
    } on HostKeyRejected catch (e) {
      tab.fail(
        e,
        state: e.decision == HostKeyDecision.changed
            ? SealState.changed
            : SealState.verify,
      );
      _emit(ConnectFailed(hostId: hostId, error: e));
    } on Exception catch (e) {
      await tab.connection?.close();
      tab.connection = null;
      // a jump host's failure, key included, leaves the target seal offline
      tab.fail(e);
      _emit(ConnectFailed(hostId: hostId, error: e));
    }
    _changed();
    return tab;
  }

  Future<({List<String> hopIds, ConnectTarget target, JumpConnection conn})>
  _openChain(String hostId) async {
    // loops, depth, missing: no socket opened
    final hopIds = resolveJumpChain(hostId, _jumpLookup);
    final hops = <ConnectTarget>[];
    for (final (i, id) in hopIds.indexed) {
      try {
        hops.add(await _targetFor(id));
      } on Exception catch (e) {
        throw JumpChainFailed(id, _openVault.hostLookup(id)!.meta.name, i, e);
      }
    }
    final target = await _targetFor(hostId);
    try {
      final conn = await connectChain(
        (hop, {over}) => _ssh.connectHop(hop, this, over: over),
        hops,
        target,
      );
      return (hopIds: hopIds, target: target, conn: conn);
    } on JumpChainFailed catch (e) {
      // The target's own error keeps its handling.
      if (e.cause case final Exception cause when e.hopIndex == hops.length) {
        throw cause;
      }
      rethrow;
    }
  }

  Future<void> _startAutoForwards(
    TerminalSession tab,
    List<PortForward> forwards,
  ) async {
    for (final forward in forwards.where((f) => f.autoStart)) {
      try {
        await startForward(tab, forward);
      } on Exception {
        // already recorded and reported; the shell stays
      }
    }
  }

  void selectTab(int index) {
    activeTab = index;
    _changed();
  }

  /// Moves the tab at [from] to [to] (indexes after the move); the shown tab stays shown.
  void moveTab(int from, int to) {
    final shown = activeSession;
    tabs.insert(to, tabs.removeAt(from));
    activeTab = shown == null ? 0 : tabs.indexOf(shown);
    _changed();
  }

  Future<void> closeTab(TerminalSession tab) async {
    trace(TraceArea.ssh, 'tab closed ${shortId(tab.hostId)}');
    tabs.remove(tab);
    _loquet.tabsChanged({for (final t in tabs) t.hostId});
    activeTab = tabs.isEmpty ? 0 : activeTab.clamp(0, tabs.length - 1);
    _changed();
    await _closeSession(tab);
  }

  /// Every tab leaves at once, without notifying; the returned future completes once their sessions closed.
  Future<void> closeAll() {
    final closing = [for (final tab in tabs) _closeSession(tab)];
    tabs.clear();
    _loquet.tabsChanged(const {});
    activeTab = 0;
    return Future.wait(closing);
  }

  /// A new session for [previous]'s host, in [previous]'s place; the old one is closed first (ports, hops).
  Future<TerminalSession> reconnect(TerminalSession previous) async {
    final index = tabs.indexOf(previous);
    await closeTab(previous);
    // connect adds its tab before its first await, so the tab moves into place now,
    // not after a host key prompt or a slow sign-in.
    final connecting = connect(previous.hostId);
    final tab = tabs.removeLast();
    tabs.insert(index.clamp(0, tabs.length), tab);
    activeTab = tabs.indexOf(tab);
    _changed();
    await connecting;
    return tab;
  }

  // Reports every running forward as stopped, then closes the shell, forwards and hops.
  Future<void> _closeSession(TerminalSession tab) async {
    for (final port in tab.forwarder?.active.keys ?? const <int>[]) {
      _emit(ForwardStopped(hostId: tab.hostId, localPort: port));
    }
    // Runs before the first await: lock clears the tabs right after.
    _sessionClosed(tab);
    await tab.close();
  }

  void _sessionClosed(TerminalSession tab) {
    if (_live.remove(tab)) _emit(SessionClosed(hostId: tab.hostId));
  }

  Future<void> startForward(TerminalSession tab, PortForward forward) async {
    await tab.forwarder!.start(forward);
    _emit(ForwardStarted(hostId: tab.hostId, forward: forward));
  }

  Future<void> stopForward(TerminalSession tab, int localPort) async {
    await tab.forwarder!.stop(localPort);
    _emit(ForwardStopped(hostId: tab.hostId, localPort: localPort));
  }

  /// The live tab's state; else `verify` until a key is trusted, then `offline`.
  SealState sealFor(String hostId) {
    final live = tabs.where((t) => t.hostId == hostId).lastOrNull;
    if (live != null) return live.state;
    return _vault()?.hostKeys.pinOf(hostId) == null
        ? SealState.verify
        : SealState.offline;
  }

  @override
  KnownHostMeta? pinnedKey(String hostId) => _openVault.hostKeys.pinOf(hostId);

  @override
  Future<bool> confirmHostKey(HostKeyCheck check) async {
    if (check.decision == HostKeyDecision.changed) {
      _emit(const HostKeyChanged());
    }
    return await dialogs?.confirmHostKey(check) ?? false;
  }

  @override
  Future<void> pinHostKey(String hostId, String keyType, String fingerprint) =>
      _openVault.hostKeys.pin(hostId, keyType, fingerprint);

  @override
  Future<String?> askPassword(String target) async =>
      dialogs?.askPassword(target);

  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async => dialogs?.answerPrompts(name, instruction, prompts);
}
