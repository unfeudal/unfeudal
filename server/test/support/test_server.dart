// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_server/src/api/app.dart';
import 'package:unfeudal_server/src/auth/secret_hash.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/maintenance.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/log/logger.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_server/src/net/client_ip.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'fake_clock.dart';
import 'fake_mailer.dart';
import 'peer.dart';
import 'test_db.dart';

const testPassword = 'correct horse battery staple';
const testSetupToken = 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ';

class TestResponse {
  TestResponse(this.status, this.headers, this.json, this.error);
  final int status;
  final Map<String, String> headers;
  final Object? json;
  final String? error;
  Map<String, Object?> get body => json! as Map<String, Object?>;
}

class TestServer {
  TestServer._(
    this.db,
    this.clock,
    this.deps,
    this.handler,
    this.logLines,
    this._dir,
  );
  final Db db;
  final FakeClock clock;
  final AppDeps deps;
  final Handler handler;
  final List<String> logLines;
  final Directory _dir;

  static Future<TestServer> start({
    Map<String, String> env = const {},
    Mailer? mailer,
  }) async {
    final dir = Directory.systemTemp.createTempSync('unfeudal_test_');
    final config = Config.load({
      'UNFEUDAL_PUBLIC_URL': 'https://vault.test',
      'UNFEUDAL_SECRET_FILE': '${dir.path}/secret.key',
      'UNFEUDAL_SETUP_TOKEN': testSetupToken,
      ...env,
    });
    final db = await openTestDb();
    await migrate(db);
    final clock = FakeClock(DateTime.utc(2026, 10, 13, 12));
    final lines = <String>[];
    final deps = await AppDeps.create(
      config,
      db,
      clock: clock,
      log: Logger(LogLevel.debug, lines.add),
      secretHash: SecretHashParams.testing,
      allowTestingKdf: true,
      mailer: mailer ?? FakeMailer(),
    );
    await ensureSetupToken(db, config.setupToken);
    return TestServer._(db, clock, deps, buildHandler(deps), lines, dir);
  }

  /// Sends `X-Unfeudal-Client: 0.1.0` unless [headers] overrides it; a header given as '' is not sent.
  Future<TestResponse> send(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String> headers = const {},
    String ip = '203.0.113.7',
  }) async {
    final all = {
      'x-unfeudal-client': '0.1.0',
      if (token != null) 'authorization': 'Bearer $token',
      ...headers,
    }..removeWhere((_, v) => v.isEmpty);
    final response = await handler(
      Request(
        method,
        Uri.parse('https://vault.test$path'),
        body: body == null ? null : (body is String ? body : jsonEncode(body)),
        headers: all,
        context: {connectionInfoKey: FakePeer(ip)},
      ),
    );
    final text = await response.readAsString();
    final Object? json = text.isEmpty ? null : jsonDecode(text);
    return TestResponse(
      response.statusCode,
      response.headers,
      json,
      json is Map ? json['error'] as String? : null,
    );
  }

  Future<TestResponse> get(
    String path, {
    String? token,
    Map<String, String> headers = const {},
    String ip = '203.0.113.7',
  }) => send('GET', path, token: token, headers: headers, ip: ip);
  Future<TestResponse> post(
    String path, {
    String? token,
    Object? body,
    Map<String, String> headers = const {},
    String ip = '203.0.113.7',
  }) => send('POST', path, token: token, body: body, headers: headers, ip: ip);
  Future<TestResponse> put(
    String path, {
    String? token,
    Object? body,
    Map<String, String> headers = const {},
    String ip = '203.0.113.7',
  }) => send('PUT', path, token: token, body: body, headers: headers, ip: ip);
  Future<TestResponse> delete(
    String path, {
    String? token,
    Object? body,
    Map<String, String> headers = const {},
    String ip = '203.0.113.7',
  }) =>
      send('DELETE', path, token: token, body: body, headers: headers, ip: ip);

  Future<void> close() async {
    await db.close();
    _dir.deleteSync(recursive: true);
  }
}

class TestSession {
  TestSession(
    this.userId,
    this.deviceId,
    this.accessToken,
    this.refreshToken,
    this.email,
    this.password,
    this.bundle,
    this.bundleVersion,
    this.account, {
    this.recoveryKey,
  });
  final String userId;
  final String deviceId;
  String accessToken;
  String refreshToken;
  final String email;
  final String password;
  final AccountBundle bundle;
  final int bundleVersion;
  final UnlockedAccount account;
  final String?
  recoveryKey; // recovery key text; set by setupOwner and createUser
}

final testCrypto = AccountCrypto(kdf: KdfParams.testing, allowTestingKdf: true);

Map<String, Object?> testDevice([String name = 'Test device']) => {
  'name': name,
  'platform': 'linux',
};

extension SetupOwner on TestServer {
  Future<TestSession> setupOwner({
    String email = 'owner@example.org',
    String password = testPassword,
  }) async {
    final acc = await testCrypto.create(password);
    final r = await post(
      '/api/v1/setup',
      body: {
        'token': testSetupToken,
        'email': email,
        'bundle': acc.bundle.toJson(),
        'authKey': b64(acc.authKey),
        'recoveryAuthKey': b64(acc.recoveryAuthKey),
        'device': testDevice(),
      },
    );
    if (r.status != 201) {
      throw StateError('setup failed: ${r.status} ${r.json}');
    }
    final session = Session.fromJson(r.json);
    return TestSession(
      session.userId,
      session.deviceId,
      session.accessToken,
      session.refreshToken,
      email.trim().toLowerCase(),
      password,
      session.bundle,
      session.bundleVersion,
      acc.unlocked,
      recoveryKey: acc.recoveryKey,
    );
  }
}

extension Accounts on TestServer {
  Future<TestSession> login(
    String email,
    String password, {
    String deviceName = 'Test device',
    String ip = '203.0.113.7',
  }) async {
    final pre = await post('/api/v1/prelogin', body: {'email': email}, ip: ip);
    final keys = await deriveMasterKeys(
      password,
      unb64(pre.body['salt'] as String),
      KdfParams.fromJson(pre.body['kdf']),
    );
    final r = await post(
      '/api/v1/login',
      body: {
        'email': email,
        'authKey': b64(keys.authKey),
        'device': testDevice(deviceName),
      },
      ip: ip,
    );
    if (r.status != 200) {
      throw StateError('login failed: ${r.status} ${r.json}');
    }
    final session = Session.fromJson(r.json);
    return TestSession(
      session.userId,
      session.deviceId,
      session.accessToken,
      session.refreshToken,
      email,
      password,
      session.bundle,
      session.bundleVersion,
      await testCrypto.unlock(session.bundle, password),
    );
  }

  /// Inserts the account directly (accounts otherwise come from invites, p6), then logs in.
  Future<TestSession> createUser(
    String email, {
    String password = testPassword,
  }) async {
    final acc = await testCrypto.create(password);
    await db.execute(
      'INSERT INTO users (id, email, bundle, auth_hash, recovery_auth_hash, created_at) '
      'VALUES (@id, @email, @bundle, @auth, @recovery, @now)',
      {
        'id': newId(),
        'email': email,
        'bundle': jsonEncode(acc.bundle.toJson()),
        'auth': await hashSecret(acc.authKey, SecretHashParams.testing),
        'recovery': await hashSecret(
          acc.recoveryAuthKey,
          SecretHashParams.testing,
        ),
        'now': iso(clock.now()),
      },
    );
    final s = await login(email, password);
    return TestSession(
      s.userId,
      s.deviceId,
      s.accessToken,
      s.refreshToken,
      email,
      password,
      s.bundle,
      s.bundleVersion,
      s.account,
      recoveryKey: acc.recoveryKey,
    );
  }
}
