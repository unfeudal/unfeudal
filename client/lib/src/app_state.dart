// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../l10n/app_localizations.dart';
import 'api/api_client.dart';
import 'audit/event_reporter.dart';
import 'debug_trace.dart';
import 'design/seal.dart';
import 'events/app_events.dart';
import 'session/auto_lock.dart';
import 'session/biometrics.dart';
import 'session/lock_machine.dart';
import 'session/session_store.dart';
import 'settings/settings.dart';
import 'loquet/loquet_controller.dart';
import 'loquet/loquet_memory.dart';
import 'loquet/loquet_mode.dart';
import 'loquet/mood.dart';
import 'loquet/reaction_engine.dart';
import 'orgs/host_binding.dart';
import 'orgs/org_controller.dart';
import 'ssh/jump_connector.dart';
import 'ssh/port_forwarder.dart';
import 'ssh/ssh_connector.dart';
import 'storage/local_mirror.dart';
import 'sync/ledger_store.dart';
import 'sync/sync_engine.dart';
import 'terminal/terminal_session.dart';
import 'vault/vault.dart';

enum AppStage { booting, login, setup, join, unlock, home, mirrorTooNew }

/// A server reached over anything but https, or plain http outside the LAN or without `plain_http_lan`.
class InsecureServer implements Exception {
  const InsecureServer();
}

/// Plain http on the LAN that the user did not confirm.
class PlainHttpRefused implements Exception {
  const PlainHttpRefused();
}

/// The platform name and its wire value; never the hostname.
DeviceInput deviceInput() {
  if (Platform.isWindows) return (name: 'Windows', platform: 'windows');
  if (Platform.isMacOS) return (name: 'macOS', platform: 'macos');
  if (Platform.isLinux) return (name: 'Linux', platform: 'linux');
  return (name: 'Other', platform: 'other');
}

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
  final hash = base64Encode((await Sha256().hash(utf8.encode(command))).bytes);
  if (ledger.startupApproval(hostId) == hash) return command;
  if (await dialogs?.confirmStartupCommand(hostName, command) != true) {
    return null; // the session opens without it
  }
  await ledger.approveStartup(hostId, hash);
  return command;
}

/// The single state root: account, local stores, vault, sync and terminal tabs.
class AppState extends ChangeNotifier implements SshCallbacks {
  AppState({
    required this.sessions,
    required this.settingsStore,
    required this._openMirror,
    http.Client? httpClient,
    SshConnector? ssh,
    this.allowTestingKdf = false,
    KdfParams kdf = KdfParams.defaults,
    LoquetMemory? loquetMemory,
    DateTime Function() loquetClock = DateTime.now,
    BiometricBackend? biometrics,
  }) : _http = httpClient ?? http.Client(),
       _biometrics = biometrics,
       biometric = biometrics == null
           ? null
           : BiometricUnlock(sessions.kv, biometrics),
       _ssh = ssh ?? SshConnector(),
       _crypto = AccountCrypto(kdf: kdf, allowTestingKdf: allowTestingKdf),
       _loquetClock = loquetClock,
       loquet = LoquetController(
         ReactionEngine(
           memory: loquetMemory ?? LoquetMemory(),
           now: loquetClock,
         ),
       ) {
    reporter.start();
  }

  final SessionStore sessions;
  final SettingsStore settingsStore;
  final bool allowTestingKdf;
  final Future<LocalMirror> Function(String userId) _openMirror;
  final http.Client _http;
  final SshConnector _ssh;

  final AccountCrypto _crypto;
  final BiometricBackend? _biometrics;

  /// The vault key sealed by the device's secure hardware; null on a platform without it.
  final BiometricUnlock? biometric;

  /// The unlocked account while the vault is open (its userKey seals the biometric wrap).
  UnlockedAccount? _account;
  final DateTime Function() _loquetClock;

  /// Sessions, forwards and shown secrets for the server's audit, when it asks for them.
  late final reporter = EventReporter(
    events: events,
    api: () => api,
    enabled: () => serverHas('client_events'),
  );

  /// Tabs whose shell opened: each leaves once, with a [SessionClosed].
  final _live = <TerminalSession>{};

  /// The mascot: local only, nothing about it is synced or logged.
  final LoquetController loquet;

  AppStage stage = AppStage.booting;
  Settings settings = const Settings();
  StoredSession? stored;
  ApiClient? api;
  LocalMirror? mirror;
  Vault? vault;
  SyncEngine? sync;
  OrgController? orgs;
  final lockMachine = LockMachine();
  final tabs = <TerminalSession>[];
  int activeTab = 0;
  SshDialogs? dialogs;
  bool deviceRevoked = false;
  bool sessionExpired = false;

  /// The sealed ledger could not be opened and restarted empty: shown once in a banner.
  bool ledgerReported = false;

  /// Shown once on the recovery-kit screen of an onboarding, then forgotten.
  String? recoveryKey;
  Enrollment? enrollment;

  /// Asked before any setup, join or login over plain http: the authKey and the tokens travel unencrypted.
  Future<bool> Function(Uri server)? confirmPlainHttp;

  final _events = StreamController<AppEvent>.broadcast();
  ApiInfo? _lastInfo;
  String? _mirrorUser;
  int _unlockFailures = 0;
  AutoLock? _autoLock;
  bool _wasOnline = true;
  Future<void> _prefsWrite = Future.value();

  Stream<AppEvent> get events => _events.stream;

  /// The account's X25519 public key, from the cached bundle (signed in or unlocked).
  Uint8List get accountPublicKey => _cachedBundle().bundle.publicKey;

  /// The server version of the last ApiInfo seen with a token, if any.
  String? get serverVersion => _lastInfo?.server ?? _storedInfo?.server;

  /// The ApiInfo the last sync round stored in the mirror.
  ApiInfo? get _storedInfo => switch (mirror?.getKv(KvKey.apiInfo)) {
    final raw? => ApiInfo.fromJson(jsonDecode(raw)),
    null => null,
  };

  /// Moves between the signed-out screens (login, setup, join).
  void show(AppStage stage) {
    this.stage = stage;
    notifyListeners();
  }

  void emit(AppEvent event) {
    if (tracing(TraceArea.ui)) trace(TraceArea.ui, 'event ${_describe(event)}');
    _events.add(event);
    loquet.show(loquet.engine.handle(event));
  }

  /// The three levels: server flag, then the orgs, then the user's pref. A server never seen yet shows the logo.
  void _refreshLoquet() {
    final mode = effectiveLoquetMode(
      serverHas('mascot'),
      orgs?.orgs ?? const [],
      settings.loquetMode,
    );
    if (mode != loquet.mode) loquet.mode = mode;
  }

  static final _conflictSuffixes = {
    for (final l in AppLocalizations.supportedLocales)
      ' ${lookupAppLocalizations(l).conflictSuffix}',
  };

  /// Loquet's resting mood, from the vault and the last sync round.
  void _refreshHealth() {
    final v = vault;
    if (v == null || !v.isUnlocked) return;
    loquet.setHealth(
      vaultHealthOf(
        v,
        now: _loquetClock(),
        lastSyncAt: sync?.lastSyncAt,
        rejected: sync?.rejected.length ?? 0,
        conflictSuffixes: _conflictSuffixes,
      ),
    );
  }

  /// The event's type, plus the host id and error type for connections; nothing from the vault.
  static String _describe(AppEvent event) => switch (event) {
    ConnectStarted(:final hostId) => 'ConnectStarted ${shortId(hostId)}',
    ConnectSucceeded(:final hostId) => 'ConnectSucceeded ${shortId(hostId)}',
    ConnectFailed(:final hostId, :final error) =>
      'ConnectFailed ${shortId(hostId)} (${error.runtimeType})',
    _ => '${event.runtimeType}',
  };

  /// From the last ApiInfo seen (a sync round or [checkServer]), else the stored one; false when none.
  /// The effective trash retention in days (0 = never purged); null before the server said.
  int? get trashDays => (_lastInfo ?? _storedInfo)?.trashDays;

  /// Where the server publishes its source (AGPL); null before the server said.
  String? get serverSource => (_lastInfo ?? _storedInfo)?.source;

  /// The KDF this client uses for new wraps (and vault exports).
  KdfParams get kdf => _crypto.kdf;

  bool serverHas(String capability) =>
      (_lastInfo ?? _storedInfo)?.has(capability) ?? false;

  Future<void> boot() async {
    settings = await settingsStore.load();
    stored = await sessions.load();
    final session = stored;
    if (session == null) {
      stage = AppStage.login;
    } else {
      try {
        await _mirrorFor(session.userId);
        stage = session.refreshToken == null ? AppStage.login : AppStage.unlock;
      } on MirrorTooNew {
        stage = AppStage
            .mirrorTooNew; // a newer client wrote it: nothing is touched
      }
    }
    _refreshLoquet();
    notifyListeners();
  }

  /// The public ApiInfo, once the transport is acceptable.
  Future<ApiInfo> checkServer(Uri server) async {
    final http = server.scheme == 'http';
    if (!http && server.scheme != 'https') throw const InsecureServer();
    if (http && !isLanHost(server)) throw const InsecureServer();
    final info = await _newApi(server).info();
    if (http) {
      if (!info.has('plain_http_lan')) throw const InsecureServer();
      if (await confirmPlainHttp?.call(server) != true) {
        throw const PlainHttpRefused();
      }
    }
    _lastInfo = info;
    _refreshLoquet();
    return info;
  }

  Future<void> setup({
    required Uri server,
    required String token,
    required String email,
    required String password,
    String? displayName,
  }) async {
    trace(TraceArea.session, 'setup');
    await _enroll(
      EnrollKind.setup,
      server,
      token,
      email,
      password,
      displayName,
    );
  }

  Future<void> acceptInvite({
    required Enrollment enrollment,
    required String email,
    required String password,
    String? displayName,
  }) async {
    trace(TraceArea.session, 'accept invite');
    this.enrollment = enrollment;
    await _enroll(
      EnrollKind.invite,
      enrollment.server,
      enrollment.token,
      email,
      password,
      displayName,
    );
  }

  Future<void> _enroll(
    EnrollKind kind,
    Uri server,
    String token,
    String email,
    String password,
    String? displayName,
  ) async {
    await checkServer(server);
    final api = _newApi(server);
    final account = await _crypto.create(password);
    final session = await api.enroll(
      kind,
      token: token,
      email: email,
      bundle: account.bundle,
      authKey: account.authKey,
      recoveryAuthKey: account.recoveryAuthKey,
      device: deviceInput(),
      locale: _uiLocale,
    );
    await _onboarded(api, session, server, email, account, displayName);
  }

  /// Leaves the recovery-kit screen: the key text is forgotten.
  void finishOnboarding() {
    recoveryKey = null;
    stage = AppStage.home;
    notifyListeners();
  }

  Future<void> login({
    required Uri server,
    required String email,
    required String password,
  }) async {
    trace(TraceArea.session, 'login');
    await checkServer(server);
    final api = _newApi(server);
    final pre = await api.prelogin(email);
    pre.kdf.ensureAcceptable(allowTesting: allowTestingKdf); // WeakKdf / UnsupportedKdf / FormatException: nothing derived, nothing sent
    final keys = await deriveMasterKeys(password, pre.salt, pre.kdf);
    final session = await api.login(
      email: email,
      authKey: keys.authKey,
      device: deviceInput(),
    );
    final unlocked = await _crypto.unlock(
      session.bundle,
      password,
    ); // checks the bundle KDF too
    await _open(api, session, server, email, unlocked);
    deviceRevoked = sessionExpired = false;
    stage = AppStage.home;
    notifyListeners();
    emit(
      DeviceAdded(
        activeDevices: (await api.devices())
            .where((d) => d.revokedAt == null)
            .length,
      ),
    );
    await _sendLocale();
  }

  /// Offline: the cached bundle opens the vault; the API resumes with the stored refresh token.
  Future<void> unlock(String password) async {
    final (:bundle, bundleVersion: _) = _cachedBundle();
    final UnlockedAccount unlocked;
    try {
      unlocked = await _crypto.unlock(bundle, password);
    } on WrongPassword {
      lockMachine.fail();
      emit(UnlockFailed(consecutive: ++_unlockFailures));
      rethrow;
    }
    _unlockFailures = 0;
    await _resume(unlocked);
  }

  /// After the key is checked: the API resumes with the stored refresh token, the vault opens, home.
  Future<void> _resume(UnlockedAccount unlocked) async {
    // the keystore holds the latest refresh token (rotations since sign-in); a stale one is a replay
    final loaded = await sessions.load();
    if (loaded == null) {
      trace(
        TraceArea.session,
        'unlock: keystore empty, using the cached session',
      );
    }
    final session = stored =
        loaded ?? stored ?? (throw StateError('no stored session'));
    if (tracing(TraceArea.session)) {
      trace(
        TraceArea.session,
        'unlock with #${await tokenTag(session.refreshToken)}',
      );
    }
    final api = _newApi(session.serverUrl)..refreshToken = session.refreshToken;
    await _startVault(api, unlocked);
    stage = AppStage.home;
    notifyListeners();
    emit(Unlocked(displayName: _displayName));
  }

  /// Hardware present, the server allows it, and the OS offers it.
  Future<bool> biometricAvailable() async =>
      biometric != null &&
      serverHas('biometric_unlock') &&
      await _biometrics!.available();

  Future<bool> enableBiometrics() async {
    final account = _account;
    if (account == null || !await biometricAvailable()) return false;
    return biometric!.enable(account.userKey, reason: _biometricReason);
  }

  Future<void> disableBiometrics() async => biometric?.disable();

  /// The public key check of `unlockWithUserKey` runs before the vault opens.
  Future<bool> unlockWithBiometrics() async {
    final bio = biometric;
    if (bio == null || !await bio.isEnabled()) return false;
    if (!serverHas('biometric_unlock')) {
      await bio.disable(); // flag off on the server: a stored wrap is wiped
      return false;
    }
    lockMachine.helloStarted();
    final userKey = await bio.unlock(reason: _biometricReason);
    if (userKey == null) {
      lockMachine.helloCancelled();
      return false;
    }
    final UnlockedAccount unlocked;
    try {
      unlocked = await _crypto.unlockWithUserKey(
        _cachedBundle().bundle,
        userKey,
      );
    } on WrongPassword {
      await bio.disable();
      lockMachine.helloCancelled();
      return false;
    }
    await _resume(unlocked);
    lockMachine.succeed();
    return true;
  }

  String get _biometricReason =>
      lookupAppLocalizations(Locale(_uiLocale ?? 'en')).biometricReason;

  /// The server turning biometric_unlock off wipes a stored wrap, once per change of the flag.
  void _checkBiometricFlag() {
    final allowed = serverHas('biometric_unlock');
    if (_biometricAllowed && !allowed) unawaited(biometric?.disable());
    _biometricAllowed = allowed;
  }

  bool _biometricAllowed = true;

  /// Keys, entries and terminal tabs go; the stage is set at once, the tabs close behind it.
  Future<void> lock() async {
    trace(TraceArea.session, 'lock (${tabs.length} tabs closed)');
    final closing = [for (final tab in tabs) _closeSession(tab)];
    tabs.clear();
    loquet.engine.tabsChanged(const {});
    activeTab = 0;
    sync?.stop();
    _autoLock?.stop();
    _account = null;
    orgs?.lock();
    vault?.lock();
    lockMachine.reset();
    stage = AppStage.unlock;
    notifyListeners();
    emit(const VaultLocked());
    await Future.wait(closing);
  }

  Future<void> signOut() async {
    trace(TraceArea.session, 'sign out');
    await biometric?.disable(); // the wrap is useless without the session
    await lock();
    await sessions.clear();
    stored = null;
    stage = AppStage.login;
    notifyListeners();
  }

  /// The current password is proved locally before anything is sent; the userKey stays the same.
  Future<void> changeMasterPassword(String current, String next) async {
    final (:bundle, :bundleVersion) = _cachedBundle();
    final unlocked = await _crypto.unlock(
      bundle,
      current,
    ); // WrongPassword: nothing sent
    final changed = await _crypto.changePassword(
      unlocked,
      bundle,
      next,
    ); // WeakPassword: nothing sent
    final currentAuthKey = (await deriveMasterKeys(
      current,
      bundle.salt,
      bundle.kdf,
    )).authKey;
    await api!.changePassword(
      currentAuthKey: currentAuthKey,
      bundle: changed.bundle,
      bundleVersion: bundleVersion,
      authKey: changed.authKey,
    );
    _saveBundle(
      changed.bundle,
      bundleVersion + 1,
    ); // userKey unchanged: a biometric wrap stays valid
  }

  /// Password change, then a new recovery kit when the server allows it (null otherwise).
  Future<String?> securityReset(String current, String next) async {
    await changeMasterPassword(current, next);
    return serverHas('recovery_kit') ? regenerateRecoveryKit(next) : null;
  }

  /// The password is proved here first; this device forgets the account only after the server deleted it.
  Future<void> deleteAccount(String password) async {
    final bundle = _cachedBundle().bundle;
    await _crypto.unlock(bundle, password); // WrongPassword: nothing sent
    final currentAuthKey = (await deriveMasterKeys(
      password,
      bundle.salt,
      bundle.kdf,
    )).authKey;
    // 409 last_owner: ApiException.orgs, nothing wiped
    await api!.deleteAccount(currentAuthKey: currentAuthKey);
    await biometric?.disable();
    await lock();
    await sessions.clear();
    mirror?.destroy();
    mirror = null;
    _mirrorUser = null;
    stored = null;
    stage = AppStage.login;
    notifyListeners();
  }

  /// New recovery key text; the server stores the new wrap (compare-and-swap on the bundle version).
  Future<String> regenerateRecoveryKit(String password) async {
    final (:bundle, :bundleVersion) = _cachedBundle();
    final unlocked = await _crypto.unlock(bundle, password);
    final rotated = await _crypto.rotateRecoveryKey(unlocked, bundle);
    final keys = await deriveMasterKeys(password, bundle.salt, bundle.kdf);
    await api!.changeRecoveryKit(
      currentAuthKey: keys.authKey,
      bundle: rotated.bundle,
      bundleVersion: bundleVersion,
      recoveryAuthKey: rotated.recoveryAuthKey,
    );
    _saveBundle(rotated.bundle, bundleVersion + 1);
    return rotated.recoveryKey;
  }

  /// New password from the recovery key; returns the new recovery key text. The server revokes every device.
  Future<String> recover({
    required Uri server,
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) async {
    trace(TraceArea.session, 'recover with the recovery key');
    await checkServer(server);
    final api = _newApi(server);
    final recoveryAuth = await recoveryAuthKey(RecoveryKey.decode(recoveryKey));
    final start = await api.recoverStart(
      email: email,
      recoveryAuthKey: recoveryAuth,
    );
    final unlocked = await _crypto.unlockWithRecovery(
      start.bundle,
      recoveryKey,
    );
    final changed = await _crypto.changePassword(
      unlocked,
      start.bundle,
      newPassword,
    );
    final rotated = await _crypto.rotateRecoveryKey(unlocked, changed.bundle);
    await api.recover(
      email: email,
      recoveryAuthKey: recoveryAuth,
      bundle: rotated.bundle,
      bundleVersion: start.bundleVersion,
      authKey: changed.authKey,
      newRecoveryAuthKey: rotated.recoveryAuthKey,
    );
    if (stored case final s? when s.email == email && s.serverUrl == server) {
      sessionExpired = true;
      await lock();
    }
    stage = AppStage.login;
    notifyListeners();
    return rotated.recoveryKey;
  }

  /// Null for a missing, trashed or unreadable host: the chain reports JumpHostMissing.
  ResolvedHost? _jumpLookup(String id) =>
      vault!.isTrashed(id) ? null : vault!.hostLookup(id)?.resolved;

  Future<ConnectTarget> _targetFor(String id) async {
    final found = vault!.hostLookup(id)!;
    final user = found.resolved.user ?? (throw const MissingUser());
    final entry = vault!.entry(id)!;
    final identityId =
        found.meta.identityMode == IdentityMode.perMember && entry.orgId != null
        ? bindingFor(vault!, id) ??
              (throw MissingBinding(id)) // never inherited, never the org's
        : found.resolved.identityId;
    return ConnectTarget(
      hostId: id,
      hostName: found.meta.name,
      address: found.meta.address,
      port: found.resolved.port,
      user: user,
      identity: identityId == null
          ? null
          : await vault!.identitySecret(identityId),
    );
  }

  /// Failures stay in the tab (seal and message), never thrown to the UI.
  Future<TerminalSession> connect(String hostId) async {
    final found =
        vault!.hostLookup(hostId) ?? (throw StateError('unknown host'));
    final tab = TerminalSession(hostId: hostId, title: found.meta.name);
    final input = tab.onUserInput;
    // only that a key was typed, never which
    tab.onUserInput = () {
      input?.call();
      loquet.engine.terminalInput();
    };
    tabs.add(tab);
    activeTab = tabs.length - 1;
    notifyListeners();
    emit(ConnectStarted(hostId: hostId));
    try {
      // loops, depth, missing: no socket opened
      final hopIds = resolveJumpChain(hostId, _jumpLookup);
      final hops = <ConnectTarget>[];
      for (final (i, id) in hopIds.indexed) {
        try {
          hops.add(await _targetFor(id));
        } on Exception catch (e) {
          throw JumpChainFailed(id, vault!.hostLookup(id)!.meta.name, i, e);
        }
      }
      final target = await _targetFor(hostId);
      final JumpConnection conn;
      try {
        conn = await JumpConnector(sshHopOpener(_ssh, this))
            .connect(hops, target);
      } on JumpChainFailed catch (e) {
        if (e.hopIndex == hops.length && e.cause is Exception) {
          throw e.cause; // the target's own error keeps its handling
        }
        rethrow;
      }
      tab.connection = conn;
      tab.attach(
        await conn.target.shell(),
        startupCommand: await startupCommandToSend(
          hostId: hostId,
          hostName: found.meta.name,
          command: found.meta.startupCommand,
          org: found.org,
          ledger: vault!.ledger,
          dialogs: dialogs,
        ),
      );
      if (hopIds.isNotEmpty) emit(JumpUsed(hostId: hostId, hopIds: hopIds));
      _live.add(tab);
      tab.addListener(() {
        // the host ended the shell
        if (tab.state == SealState.offline) _sessionClosed(tab);
      });
      emit(
        ConnectSucceeded(
          hostId: hostId,
          user: target.user,
          tags: found.meta.tags,
        ),
      );
      tab.forwarder = PortForwarder(conn.target.forwardLocal);
      for (final f in found.meta.forwards.where((f) => f.autoStart)) {
        try {
          await startForward(tab, f);
        } on Exception {
          // already recorded and reported; the shell stays
        }
      }
    } on HostKeyRejected catch (e) {
      tab.fail(
        e,
        state: e.decision == HostKeyDecision.changed
            ? SealState.changed
            : SealState.verify,
      );
      emit(ConnectFailed(hostId: hostId, error: e));
    } on Exception catch (e) {
      await tab.connection?.close();
      tab.connection = null;
      // a jump host's failure, key included, leaves the target seal offline
      tab.fail(e);
      emit(ConnectFailed(hostId: hostId, error: e));
    }
    notifyListeners();
    return tab;
  }

  void selectTab(int index) {
    activeTab = index;
    notifyListeners();
  }

  Future<void> closeTab(TerminalSession tab) async {
    trace(TraceArea.ssh, 'tab closed ${shortId(tab.hostId)}');
    tabs.remove(tab);
    loquet.engine.tabsChanged({for (final t in tabs) t.hostId});
    activeTab = tabs.isEmpty ? 0 : activeTab.clamp(0, tabs.length - 1);
    notifyListeners();
    await _closeSession(tab);
  }

  /// A new session for [previous]'s host, in [previous]'s place; the old one is closed first (ports, hops).
  Future<TerminalSession> reconnect(TerminalSession previous) async {
    final index = tabs.indexOf(previous);
    await closeTab(previous);
    final tab = await connect(previous.hostId);
    tabs
      ..remove(tab)
      ..insert(index.clamp(0, tabs.length), tab);
    activeTab = tabs.indexOf(tab);
    notifyListeners();
    return tab;
  }

  /// Reports every running forward as stopped, then closes the shell, forwards and hops.
  Future<void> _closeSession(TerminalSession tab) async {
    for (final port in tab.forwarder?.active.keys ?? const <int>[]) {
      emit(ForwardStopped(hostId: tab.hostId, localPort: port));
    }
    _sessionClosed(
      tab,
    ); // before the first await: lock clears the tabs right after
    await tab.close();
  }

  void _sessionClosed(TerminalSession tab) {
    if (_live.remove(tab)) emit(SessionClosed(hostId: tab.hostId));
  }

  Future<void> startForward(TerminalSession tab, PortForward f) async {
    try {
      await tab.forwarder!.start(f);
    } on Exception catch (e) {
      emit(ForwardFailed(hostId: tab.hostId, localPort: f.localPort, error: e));
      rethrow;
    }
    emit(ForwardStarted(hostId: tab.hostId, forward: f));
  }

  Future<void> stopForward(TerminalSession tab, int localPort) async {
    await tab.forwarder!.stop(localPort);
    emit(ForwardStopped(hostId: tab.hostId, localPort: localPort));
  }

  /// The live tab's state; else `verify` until a key is trusted, then `offline`.
  SealState sealFor(String hostId) {
    final live = tabs.where((t) => t.hostId == hostId).lastOrNull;
    if (live != null) return live.state;
    return vault?.trustedPin(hostId) == null
        ? SealState.verify
        : SealState.offline;
  }

  @override
  KnownHostMeta? pinnedKey(String hostId) => vault!.trustedPin(hostId);

  @override
  Future<bool> confirmHostKey(HostKeyCheck check) async {
    if (check.decision == HostKeyDecision.changed) {
      emit(HostKeyChanged(hostId: check.hostId));
    }
    return await dialogs?.confirmHostKey(check) ?? false;
  }

  @override
  Future<void> pinHostKey(String hostId, String keyType, String fingerprint) =>
      vault!.pinHostKey(hostId, keyType, fingerprint);

  @override
  Future<String?> askPassword(String target) async =>
      dialogs?.askPassword(target);

  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async => dialogs?.answerPrompts(name, instruction, prompts);

  /// Saved on this machine; synced prefs also go to the profile item (removed keys as null), one write at a time.
  Future<void> updateSettings(Settings next) async {
    final previous = settings;
    settings = next;
    await settingsStore.save(next);
    if (next.themeMode != previous.themeMode) {
      emit(ThemeChanged(mode: next.themeMode));
    }
    _refreshLoquet();
    notifyListeners();
    if (next.locale != previous.locale) await _sendLocale();
    final prefs = next.toPrefs(), before = previous.toPrefs();
    final v = vault;
    if (mapEquals(prefs, before) ||
        v == null ||
        !v.isUnlocked ||
        (sync?.readOnly ?? true)) {
      return;
    }
    final changes = {
      for (final key in before.keys)
        if (!prefs.containsKey(key)) key: null,
      ...prefs,
    };
    await (_prefsWrite = _prefsWrite.then((_) => v.setPrefs(changes)));
  }

  Future<List<Device>> loadDevices() => api!.devices();

  /// Revoking this device signs out.
  Future<void> revokeDevice(String id) async {
    await api!.revokeDevice(id);
    if (id == stored?.deviceId) {
      deviceRevoked = true;
      await signOut();
    }
  }

  void onHomeMounted() {
    sync?.start();
    _autoLock = AutoLock(
      timeout: () => Duration(minutes: settings.autoLockMinutes),
      onLock: () {
        trace(
          TraceArea.session,
          'auto-lock after ${settings.autoLockMinutes} min idle',
        );
        unawaited(lock());
      },
      onIdle: () => emit(const UserIdle()),
    )..start();
  }

  void onHomeUnmounted() {
    sync?.stop();
    _autoLock?.stop();
  }

  void activity() {
    _autoLock?.activity();
    loquet.show(loquet.engine.wake());
  }

  /// Synced prefs from the profile item apply here and are cached in settings.json; never written back.
  void _applySyncedPrefs() {
    final prefs = vault?.profile.prefs ?? const {};
    if (prefs.isEmpty) return;
    final next = settings.withPrefs(prefs);
    if (next == settings) return;
    settings = next;
    unawaited(settingsStore.save(next));
    _refreshLoquet();
    notifyListeners();
  }

  void _onSyncChanged() {
    final engine = sync!;
    if (engine.online != _wasOnline) {
      _wasOnline = engine.online;
      emit(engine.online ? const CameOnline() : const WentOffline());
    }
    _lastInfo = _storedInfo ?? _lastInfo;
    _checkBiometricFlag();
    _refreshLoquet();
    _refreshHealth();
    notifyListeners();
  }

  String? get _displayName => vault?.profile.displayName ?? stored?.displayName;

  /// The name shown beside Loquet in the sidebar.
  String? get accountName => _displayName;

  /// The language of the security mails; best effort, retried at the next sign-in or change.
  Future<void> _sendLocale() async {
    try {
      await api?.setLocale(_uiLocale ?? 'en');
    } on NetworkException {
      // offline
    } on ApiException {
      // refused: the server keeps its value
    } on ReadOnlyException {
      // this client may not write to this server
    }
  }

  String? get _uiLocale {
    if (settings.locale case final locale?) return locale;
    final system = PlatformDispatcher.instance.locale.languageCode;
    return AppLocalizations.supportedLocales.any(
          (l) => l.languageCode == system,
        )
        ? system
        : null;
  }

  ApiClient _newApi(Uri server) => ApiClient(server, _http);

  Future<void> _onboarded(
    ApiClient api,
    Session session,
    Uri server,
    String email,
    NewAccount account,
    String? displayName,
  ) async {
    await _open(api, session, server, email, account.unlocked);
    if (displayName != null) await vault!.setDisplayName(displayName);
    recoveryKey = account.recoveryKey;
    stage = AppStage.setup;
    notifyListeners();
  }

  Future<void> _open(
    ApiClient api,
    Session session,
    Uri server,
    String email,
    UnlockedAccount unlocked,
  ) async {
    final next = StoredSession(
      serverUrl: server,
      userId: session.userId,
      deviceId: session.deviceId,
      email: email,
      refreshToken: session.refreshToken,
      isInstanceOwner: session.isInstanceOwner,
      displayName: stored?.userId == session.userId
          ? stored?.displayName
          : null,
    );
    await sessions.save(next);
    stored = next;
    await _mirrorFor(session.userId);
    _saveBundle(session.bundle, session.bundleVersion);
    await _startVault(api, unlocked);
    emit(Unlocked(displayName: _displayName));
  }

  Future<void> _startVault(ApiClient api, UnlockedAccount unlocked) async {
    _account = unlocked;
    final m = mirror!;
    sync?.dispose();
    vault?.removeListener(_applySyncedPrefs);
    vault?.removeListener(_refreshHealth);
    orgs?.removeListener(_onOrgsChanged);
    api.onTokens = (t) => sessions.saveRefreshToken(t.refreshToken);
    final engine = SyncEngine(api: api, mirror: m, deviceId: stored!.deviceId);
    final v = Vault(mirror: m, ledger: LedgerStore(m), write: engine.write);
    final suffix =
        ' ${lookupAppLocalizations(Locale(_uiLocale ?? 'en')).conflictSuffix}';
    final o = OrgController(
      mirror: m,
      vault: v,
      api: api,
      sync: engine,
      userId: stored!.userId,
      publicKey: accountPublicKey,
      emit: emit,
      online: () => engine.online,
    );
    engine
      ..copyOf = ((mine, {required personal}) =>
          mine.scope == ItemScope.org && !personal
          ? o.writer.conflictCopy(mine, suffix: suffix)
          : v.conflictCopy(mine, suffix: suffix))
      ..onOrgBlock = o.onBlock
      ..onChanged = v.reload
      ..onUnauthorized = ((reason) => unawaited(_sessionEnded(reason)))
      ..onRestoreAccepted = v.ledger.reset;
    this.api = api;
    sync = engine;
    vault = v;
    orgs = o;

    ledgerReported = !await v.unlock(unlocked.userKey);
    await o.unlock(unlocked);
    o.addListener(_onOrgsChanged);
    v.addListener(_applySyncedPrefs);
    v.addListener(_refreshHealth);
    engine.addListener(_onSyncChanged);
    _applySyncedPrefs();
    _refreshHealth();
  }

  void _onOrgsChanged() {
    _refreshLoquet();
    notifyListeners();
  }

  /// The server ended the session: back to login, mirror, outbox and stored session kept.
  Future<void> _sessionEnded(String? reason) async {
    trace(
      TraceArea.session,
      'session ended by the server: ${reason ?? 'no reason'}',
    );
    deviceRevoked = reason == UnauthorizedReason.deviceRevoked.wire;
    sessionExpired = !deviceRevoked;
    if (deviceRevoked) unawaited(biometric?.disable()); // other endings keep it
    await lock(); // first: stops sync and the vault before any await below
    stage = AppStage.login;
    notifyListeners();
    await sessions.forgetRefreshToken();
    stored = await sessions.load() ?? stored;
  }

  /// The mirror of [userId]: kept open across locks, replaced for another account.
  Future<void> _mirrorFor(String userId) async {
    if (mirror != null && _mirrorUser == userId) return;
    mirror?.close();
    mirror = await _openMirror(userId);
    _mirrorUser = userId;
  }

  ({AccountBundle bundle, int bundleVersion}) _cachedBundle() {
    final raw =
        mirror?.getKv(KvKey.bundle) ?? (throw StateError('no cached bundle'));
    final json = jsonDecode(raw) as Map<String, Object?>;
    return (
      bundle: AccountBundle.fromJson(json['bundle']),
      bundleVersion: json['bundleVersion']! as int,
    );
  }

  void _saveBundle(AccountBundle bundle, int bundleVersion) => mirror!.setKv(
    KvKey.bundle,
    jsonEncode({'bundle': bundle.toJson(), 'bundleVersion': bundleVersion}),
  );

  @override
  void dispose() {
    sync?.dispose();
    unawaited(_events.close());
    super.dispose();
  }
}
