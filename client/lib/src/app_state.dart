// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../l10n/app_localizations.dart';
import 'api/api_client.dart';
import 'app_state_types.dart';
import 'audit/event_reporter.dart';
import 'debug_trace.dart';
import 'events/app_events.dart';
import 'loquet/loquet_controller.dart';
import 'loquet/loquet_memory.dart';
import 'loquet/loquet_mode.dart';
import 'loquet/mood.dart';
import 'loquet/reaction_engine.dart';
import 'orgs/org_controller.dart';
import 'session/auto_lock.dart';
import 'session/biometrics.dart';
import 'session/credentials.dart';
import 'session/lock_machine.dart';
import 'session/session_store.dart';
import 'session/sign_in.dart';
import 'settings/settings.dart';
import 'ssh/connections.dart';
import 'ssh/ssh_connector.dart';
import 'storage/local_mirror.dart';
import 'sync/ledger_store.dart';
import 'sync/server_info.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_watch.dart';
import 'vault/vault.dart';

export 'app_state_types.dart';

/// The single state root: account, local stores, vault, sync and terminal tabs.
class AppState extends ChangeNotifier {
  AppState({
    required this.sessions,
    required this.settingsStore,
    required this._openMirror,
    http.Client? httpClient,
    SshConnector? ssh,
    KdfParams kdf = KdfParams.defaults,
    KdfParams kdfFloor = KdfParams.defaults,
    LoquetMemory? loquetMemory,
    DateTime Function() loquetClock = DateTime.now,
    BiometricBackend? biometrics,
  }) : _http = httpClient ?? http.Client(),
       _biometricBackend = biometrics,
       _ssh = ssh ?? SshConnector(),
       crypto = AccountCrypto(kdf: kdf, kdfFloor: kdfFloor),
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
  final Future<LocalMirror> Function(String userId) _openMirror;
  final http.Client _http;
  final SshConnector _ssh;

  /// The KDF this client uses for new wraps (and vault exports), and the floor it accepts.
  final AccountCrypto crypto;

  final BiometricBackend? _biometricBackend;

  /// The vault key sealed by the device's secure hardware; null on a platform without it.
  late final biometrics = switch (_biometricBackend) {
    final backend? => BiometricGate(
      BiometricUnlock(sessions.kv, backend),
      allowed: () => serverInfo.has(Flag.biometricUnlock),
      reason: () =>
          lookupAppLocalizations(Locale(settings.uiLocale ?? 'en'))
              .biometricReason,
    ),
    null => null,
  };

  // Held while the vault is open: its userKey seals the biometric wrap.
  UnlockedAccount? _account;
  final DateTime Function() _loquetClock;

  /// Sessions, forwards and shown secrets for the server's audit, when it asks for them.
  late final reporter = EventReporter(
    events: events,
    api: () => api,
    enabled: () => serverInfo.has(Flag.clientEvents),
  );

  late final serverInfo = ServerInfo(() => mirror);
  late final credentials = Credentials(
    crypto: crypto,
    api: () => api!,
    mirror: () => mirror!,
    serverHas: serverInfo.has,
  );
  late final connections = Connections(
    ssh: _ssh,
    vault: () => vault,
    emit: emit,
    loquet: loquet.engine,
    changed: notifyListeners,
  );

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
  SignOutReason? signedOutBecause;

  /// The sealed ledger could not be opened and restarted empty: shown once in a banner.
  bool ledgerReported = false;

  /// Shown once on the recovery-kit screen of an onboarding, then forgotten.
  String? recoveryKey;
  Enrollment? enrollment;

  /// Asked before any setup, join or login over plain http: the authKey and the tokens travel unencrypted.
  Future<bool> Function(Uri server)? confirmPlainHttp;

  late final _signIn = SignIn(_http, crypto);
  final _events = StreamController<AppEvent>.broadcast();
  String? _mirrorUser;
  AutoLock? _autoLock;
  late final _syncWatch = SyncWatch(
    emit: emit,
    notify: notifyListeners,
    onRound: () {
      serverInfo.last = sync!.storedInfo ?? serverInfo.last;
      biometrics?.checkFlag();
      _refreshLoquet();
      _refreshHealth();
    },
    onEntries: _refreshHealth,
  );
  Future<void> _prefsWrite = Future.value();

  Stream<AppEvent> get events => _events.stream;

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

  // The three levels: server flag, then the orgs, then the user's pref. A server never seen yet shows the logo.
  void _refreshLoquet() {
    final mode = effectiveLoquetMode(
      serverFlag: serverInfo.has(Flag.mascot),
      orgSettings: orgs?.orgs ?? const [],
      pref: settings.loquetMode,
    );
    if (mode != loquet.mode) loquet.mode = mode;
  }

  static final _conflictSuffixes = {
    for (final l in AppLocalizations.supportedLocales)
      ' ${lookupAppLocalizations(l).conflictSuffix}',
  };

  // Loquet's resting mood comes from the vault and the last sync round.
  void _refreshHealth() {
    final v = vault;
    if (v == null || !v.isUnlocked) return;
    loquet.setHealth(
      vaultHealthOf(
        v,
        now: _loquetClock(),
        lastSyncAt: sync?.lastSyncAt,
        rejected: sync?.rejectedIds.length ?? 0,
        conflictSuffixes: _conflictSuffixes,
      ),
    );
  }

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
    final info = await _signIn.check(
      server,
      confirmPlainHttp: confirmPlainHttp,
    );
    serverInfo.last = info;
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
      server: server,
      token: token,
      email: email,
      password: password,
      displayName: displayName,
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
      server: enrollment.server,
      token: enrollment.token,
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  Future<void> _enroll(
    EnrollKind kind, {
    required Uri server,
    required String token,
    required String email,
    required String password,
    String? displayName,
  }) async {
    await checkServer(server);
    final (:api, :session, :account) = await _signIn.enroll(
      kind,
      server: server,
      token: token,
      email: email,
      password: password,
      locale: settings.uiLocale,
    );
    await _open(
      api,
      session,
      server: server,
      email: email,
      unlocked: account.unlocked,
    );
    if (displayName != null) await vault!.profile.setDisplayName(displayName);
    recoveryKey = account.recoveryKey;
    stage = AppStage.setup;
    notifyListeners();
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
    final (:api, :session, :unlocked) = await _signIn.login(
      server: server,
      email: email,
      password: password,
    );
    await _open(api, session, server: server, email: email, unlocked: unlocked);
    signedOutBecause = null;
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
    final (:bundle, bundleVersion: _) = mirror!.cachedBundle;
    final UnlockedAccount unlocked;
    try {
      unlocked = await crypto.unlock(bundle, password);
    } on WrongPassword {
      lockMachine.fail();
      emit(UnlockFailed(consecutive: lockMachine.failures));
      rethrow;
    }
    lockMachine.failures = 0;
    await _resume(unlocked);
  }

  // After the key is checked: the API resumes with the stored refresh token, the vault opens, home.
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
    final api = ApiClient(session.serverUrl, _http)
      ..refreshToken = session.refreshToken;
    await _startVault(api, unlocked);
    stage = AppStage.home;
    notifyListeners();
    emit(Unlocked(displayName: displayName));
  }

  Future<bool> enableBiometrics() async {
    final account = _account;
    return account != null &&
        (await biometrics?.enable(account.userKey) ?? false);
  }

  /// The public key check of `unlockWithUserKey` runs before the vault opens.
  Future<bool> unlockWithBiometrics() async {
    final bio = biometrics;
    if (bio == null || !await bio.isOffered()) return false;
    lockMachine.helloStarted();
    final userKey = await bio.userKey();
    if (userKey == null) {
      lockMachine.helloCancelled();
      return false;
    }
    final UnlockedAccount unlocked;
    try {
      unlocked = await crypto.unlockWithUserKey(
        mirror!.cachedBundle.bundle,
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

  /// Keys, entries and terminal tabs go; the stage is set at once, the tabs close behind it.
  Future<void> lock() async {
    trace(TraceArea.session, 'lock (${connections.tabs.length} tabs closed)');
    final closing = connections.closeAll();
    sync?.stop();
    _autoLock?.stop();
    _account = null;
    orgs?.lock();
    vault?.lock();
    lockMachine.reset();
    stage = AppStage.unlock;
    notifyListeners();
    emit(const VaultLocked());
    await closing;
  }

  Future<void> signOut() async {
    trace(TraceArea.session, 'sign out');
    await biometrics?.disable(); // the wrap is useless without the session
    await lock();
    await sessions.clear();
    stored = null;
    stage = AppStage.login;
    notifyListeners();
  }

  /// The password is proved here first; this device forgets the account only after the server deleted it.
  Future<void> deleteAccount(String password) async {
    // WrongPassword throws here, before anything is sent.
    final proved = await crypto.unlockWithAuthKey(
      mirror!.cachedBundle.bundle,
      password,
    );
    // 409 last_owner: ApiException.orgs, nothing wiped
    await api!.deleteAccount(currentAuthKey: proved.authKey);
    await biometrics?.disable();
    await lock();
    await sessions.clear();
    mirror?.destroy();
    mirror = null;
    _mirrorUser = null;
    stored = null;
    stage = AppStage.login;
    notifyListeners();
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
    final newRecoveryKey = await _signIn.recover(
      server: server,
      email: email,
      recoveryKey: recoveryKey,
      newPassword: newPassword,
    );
    if (stored case final s? when s.email == email && s.serverUrl == server) {
      signedOutBecause = SignOutReason.sessionExpired;
      await lock();
    }
    stage = AppStage.login;
    notifyListeners();
    return newRecoveryKey;
  }

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
    await (_prefsWrite = _prefsWrite.then((_) => v.profile.setPrefs(changes)));
  }

  /// Revoking this device signs out.
  Future<void> revokeDevice(String id) async {
    await api!.revokeDevice(id);
    if (id == stored?.deviceId) {
      signedOutBecause = SignOutReason.deviceRevoked;
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

  // Synced prefs from the profile item apply here and are cached in settings.json; never written back.
  void _applySyncedPrefs() {
    final prefs = vault?.profile.meta.prefs ?? const {};
    if (prefs.isEmpty) return;
    final next = settings.withPrefs(prefs);
    if (next == settings) return;
    settings = next;
    unawaited(settingsStore.save(next));
    _refreshLoquet();
    notifyListeners();
  }

  /// The name shown beside Loquet in the sidebar.
  String? get displayName =>
      vault?.profile.meta.displayName ?? stored?.displayName;

  // The language of the security mails; best effort, retried at the next sign-in or change.
  Future<void> _sendLocale() async {
    try {
      await api?.setLocale(settings.uiLocale ?? 'en');
    } on NetworkException {
      // offline
    } on ApiException {
      // refused: the server keeps its value
    } on ReadOnlyException {
      // this client may not write to this server
    }
  }

  Future<void> _open(
    ApiClient api,
    Session session, {
    required Uri server,
    required String email,
    required UnlockedAccount unlocked,
  }) async {
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
    mirror!.cacheBundle(session.bundle, session.bundleVersion);
    await _startVault(api, unlocked);
    emit(Unlocked(displayName: displayName));
  }

  Future<void> _startVault(ApiClient api, UnlockedAccount unlocked) async {
    _account = unlocked;
    final m = mirror!;
    sync?.dispose();
    vault?.removeListener(_applySyncedPrefs);
    orgs?.removeListener(_onOrgsChanged);
    api.onTokens = (t) => sessions.saveRefreshToken(t.refreshToken);
    final engine = SyncEngine(api: api, mirror: m, deviceId: stored!.deviceId);
    final v = Vault(mirror: m, ledger: LedgerStore(m), write: engine.writeAll);
    final suffix =
        ' ${lookupAppLocalizations(Locale(settings.uiLocale ?? 'en')).conflictSuffix}';
    final o = OrgController(
      mirror: m,
      vault: v,
      api: api,
      sync: engine,
      userId: stored!.userId,
      publicKey: m.cachedBundle.bundle.publicKey,
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

    await o.unlock(unlocked);
    ledgerReported = !await v.unlock(unlocked.userKey);
    o.pins.seed();
    o.addListener(_onOrgsChanged);
    v.addListener(_applySyncedPrefs);
    _syncWatch.watch(engine, v, m);
    _applySyncedPrefs();
    _refreshHealth();
  }

  void _onOrgsChanged() {
    _refreshLoquet();
    notifyListeners();
  }

  // The server ended the session: back to login, mirror, outbox and stored session kept.
  Future<void> _sessionEnded(UnauthorizedReason? reason) async {
    trace(
      TraceArea.session,
      'session ended by the server: ${reason?.wire ?? 'no reason'}',
    );
    final revoked = reason == UnauthorizedReason.deviceRevoked;
    signedOutBecause = revoked
        ? SignOutReason.deviceRevoked
        : SignOutReason.sessionExpired;
    if (revoked) unawaited(biometrics?.disable()); // other endings keep it
    await lock(); // first: stops sync and the vault before any await below
    stage = AppStage.login;
    notifyListeners();
    await sessions.forgetRefreshToken();
    stored = await sessions.load() ?? stored;
  }

  // The mirror of userId: kept open across locks, replaced for another account.
  Future<void> _mirrorFor(String userId) async {
    if (mirror != null && _mirrorUser == userId) return;
    mirror?.close();
    mirror = await _openMirror(userId);
    _mirrorUser = userId;
  }

  @override
  void dispose() {
    sync?.dispose();
    unawaited(_events.close());
    super.dispose();
  }
}

// The event's type, plus the host id and error type for connections; nothing from the vault.
String _describe(AppEvent event) => switch (event) {
  ConnectStarted(:final hostId) => 'ConnectStarted ${shortId(hostId)}',
  ConnectSucceeded(:final hostId) => 'ConnectSucceeded ${shortId(hostId)}',
  ConnectFailed(:final hostId, :final error) =>
    'ConnectFailed ${shortId(hostId)} (${error.runtimeType})',
  _ => '${event.runtimeType}',
};
