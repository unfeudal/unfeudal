// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../l10n/app_localizations.dart';
import 'api/api_client.dart';
import 'events/app_events.dart';
import 'session/lock_machine.dart';
import 'session/session_store.dart';
import 'settings/settings.dart';
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

/// The single state root: account, local stores, vault, sync and terminal tabs.
class AppState extends ChangeNotifier {
  AppState({
    required this.sessions,
    required this.settingsStore,
    required this._openMirror,
    http.Client? httpClient,

    this.allowTestingKdf = false,
    KdfParams kdf = KdfParams.defaults,
  }) : _http = httpClient ?? http.Client(),
       _crypto = AccountCrypto(kdf: kdf, allowTestingKdf: allowTestingKdf);

  final SessionStore sessions;
  final SettingsStore settingsStore;
  final bool allowTestingKdf;
  final Future<LocalMirror> Function(String userId) _openMirror;
  final http.Client _http;

  final AccountCrypto _crypto;

  AppStage stage = AppStage.booting;
  Settings settings = const Settings();
  StoredSession? stored;
  ApiClient? api;
  LocalMirror? mirror;
  Vault? vault;
  SyncEngine? sync;
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
  Uint8List? accountPublicKey;

  /// Asked before any setup, join or login over plain http: the authKey and the tokens travel unencrypted.
  Future<bool> Function(Uri server)? confirmPlainHttp;

  final _events = StreamController<AppEvent>.broadcast();
  ApiInfo? _lastInfo;
  String? _mirrorUser;
  int _unlockFailures = 0;

  Stream<AppEvent> get events => _events.stream;

  void emit(AppEvent event) => _events.add(event);

  /// From the last ApiInfo seen (a sync round or [checkServer]), else the stored one; false when none.
  bool serverHas(String capability) {
    if (_lastInfo case final info?) return info.has(capability);
    final raw = mirror?.getKv(KvKey.apiInfo);
    return raw != null && ApiInfo.fromJson(jsonDecode(raw)).has(capability);
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
        stage = AppStage.unlock;
      } on MirrorTooNew {
        stage = AppStage
            .mirrorTooNew; // a newer client wrote it: nothing is touched
      }
    }
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
    return _lastInfo = info;
  }

  Future<void> setup({
    required Uri server,
    required String token,
    required String email,
    required String password,
    String? displayName,
  }) async {
    await checkServer(server);
    final api = _newApi(server);
    final account = await _crypto.create(password);
    final session = await api.setup(
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

  Future<void> acceptInvite({
    required Enrollment enrollment,
    required String email,
    required String password,
    String? displayName,
  }) async {
    this.enrollment = enrollment;
    await checkServer(enrollment.server);
    final api = _newApi(enrollment.server);
    final account = await _crypto.create(password);
    final session = await api.acceptInvite(
      token: enrollment.token,
      email: email,
      bundle: account.bundle,
      authKey: account.authKey,
      recoveryAuthKey: account.recoveryAuthKey,
      device: deviceInput(),
      locale: _uiLocale,
    );
    await _onboarded(
      api,
      session,
      enrollment.server,
      email,
      account,
      displayName,
    );
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
  }

  /// Offline: the cached bundle opens the vault; the API resumes with the stored refresh token.
  Future<void> unlock(String password) async {
    final session = stored ?? (throw StateError('no stored session'));
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
    final api = _newApi(session.serverUrl)..refreshToken = session.refreshToken;
    await _startVault(api, unlocked);
    stage = AppStage.home;
    notifyListeners();
    emit(Unlocked(displayName: _displayName));
  }

  /// Keys, entries and terminal tabs go; the stage is set at once, the tabs close behind it.
  Future<void> lock() async {
    final closing = [for (final tab in tabs) tab.close()];
    tabs.clear();
    activeTab = 0;
    sync?.stop();
    vault?.lock();
    lockMachine.reset();
    stage = AppStage.unlock;
    notifyListeners();
    emit(const VaultLocked());
    await Future.wait(closing);
  }

  Future<void> signOut() async {
    await lock();
    await sessions.clear();
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

  String? get _displayName => vault?.profile.displayName ?? stored?.displayName;

  String? get _uiLocale {
    if (settings.locale case final locale?) return locale;
    final system = PlatformDispatcher.instance.locale.languageCode;
    return const ['en', 'fr'].contains(system) ? system : null;
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
    final m = mirror!;
    sync?.dispose();
    api.onTokens = (t) => sessions.saveRefreshToken(t.refreshToken);
    final engine = SyncEngine(api: api, mirror: m, deviceId: stored!.deviceId);
    final v = Vault(mirror: m, ledger: LedgerStore(m), write: engine.write);
    final suffix =
        ' ${lookupAppLocalizations(Locale(_uiLocale ?? 'en')).conflictSuffix}';
    engine
      ..copyOf = ((mine, {required personal}) =>
          v.conflictCopy(mine, suffix: suffix))
      ..onChanged = v.reload
      ..onUnauthorized = ((reason) => unawaited(_sessionEnded(reason)))
      ..onRestoreAccepted = v.ledger.reset;
    this.api = api;
    sync = engine;
    vault = v;
    accountPublicKey = unlocked.bundle.publicKey;
    ledgerReported = !await v.unlock(unlocked.userKey);
  }

  /// The server ended the session: back to login, mirror, outbox and stored session kept.
  Future<void> _sessionEnded(String? reason) async {
    deviceRevoked = reason == UnauthorizedReason.deviceRevoked.wire;
    sessionExpired = !deviceRevoked;
    await lock();
    stage = AppStage.login;
    notifyListeners();
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
