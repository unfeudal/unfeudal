// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../app_state_types.dart';

/// Creates, proves or recovers an account on a server; holds no app state.
/// Each flow expects [check] to have accepted the server first.
class SignIn {
  SignIn(this._http, this._crypto);

  final http.Client _http;
  final AccountCrypto _crypto;

  /// The public ApiInfo, once the transport is acceptable.
  Future<ApiInfo> check(
    Uri server, {
    required Future<bool> Function(Uri server)? confirmPlainHttp,
  }) async {
    final isPlainHttp = server.scheme == 'http';
    if (!isPlainHttp && server.scheme != 'https') throw const InsecureServer();
    if (isPlainHttp && !isLanHost(server)) throw const InsecureServer();
    final info = await ApiClient(server, _http).info();
    if (isPlainHttp) {
      if (!info.has(Flag.plainHttpLan)) throw const InsecureServer();
      if (await confirmPlainHttp?.call(server) != true) {
        throw const PlainHttpRefused();
      }
    }
    return info;
  }

  /// A new account, enrolled with a setup token or an invite.
  Future<({ApiClient api, Session session, NewAccount account})> enroll(
    EnrollKind kind, {
    required Uri server,
    required String token,
    required String email,
    required String password,
    required String? locale,
  }) async {
    final api = ApiClient(server, _http);
    final account = await _crypto.create(password);
    final session = await api.enroll(
      kind,
      token: token,
      email: email,
      bundle: account.bundle,
      authKey: account.authKey,
      recoveryAuthKey: account.recoveryAuthKey,
      device: deviceInput(),
      locale: locale,
    );
    return (api: api, session: session, account: account);
  }

  Future<({ApiClient api, Session session, UnlockedAccount unlocked})> login({
    required Uri server,
    required String email,
    required String password,
  }) async {
    final api = ApiClient(server, _http);
    final pre = await api.prelogin(email);
    // WeakKdf / UnsupportedKdf / FormatException: nothing derived, nothing sent
    pre.kdf.ensureAcceptable(floor: _crypto.kdfFloor);
    final keys = await deriveMasterKeys(password, pre.salt, pre.kdf);
    final session = await api.login(
      email: email,
      authKey: keys.authKey,
      device: deviceInput(),
    );
    // the prelogin derivation opens a bundle of the same salt and KDF; any other is checked and derived again
    final sameKdf =
        listEquals(session.bundle.salt, pre.salt) &&
        jsonEncode(session.bundle.kdf.toJson()) == jsonEncode(pre.kdf.toJson());
    final unlocked = sameKdf
        ? await _crypto.unlockWithEncKey(session.bundle, keys.encKey)
        : await _crypto.unlock(session.bundle, password);
    return (api: api, session: session, unlocked: unlocked);
  }

  /// New password from the recovery key; returns the new recovery key text. The server revokes every device.
  Future<String> recover({
    required Uri server,
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) async {
    final api = ApiClient(server, _http);
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
    return rotated.recoveryKey;
  }
}
