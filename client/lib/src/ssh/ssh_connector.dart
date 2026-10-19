// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../debug_trace.dart';
import 'jump_connector.dart';

enum HostKeyDecision { trusted, unknown, changed }

/// No pin → unknown; same type and fingerprint → trusted; anything else → changed.
HostKeyDecision decideHostKey(
  KnownHostMeta? pinned,
  String keyType,
  String fingerprint,
) {
  if (pinned == null) return HostKeyDecision.unknown;
  return pinned.keyType == keyType && pinned.sha256Fingerprint == fingerprint
      ? HostKeyDecision.trusted
      : HostKeyDecision.changed;
}

class HostKeyCheck {
  const HostKeyCheck({
    required this.hostId,
    required this.hostName,
    required this.keyType,
    required this.fingerprint,
    required this.decision,
    this.pinned,
  });

  final String hostId;
  final String hostName;
  final String keyType;
  final String fingerprint;
  final HostKeyDecision decision;

  /// The recorded key, for a changed one.
  final KnownHostMeta? pinned;
}

class HostKeyRejected implements Exception {
  const HostKeyRejected(this.decision, {this.hostId});
  final HostKeyDecision decision;

  /// The hop whose key was refused.
  final String? hostId;

  @override
  String toString() => 'HostKeyRejected(${decision.name})';
}

class SshPrompt {
  const SshPrompt(this.text, this.echo);
  final String text;
  final bool echo;
}

/// No user resolved for the host, from the host or its folders.
class MissingUser implements Exception {
  const MissingUser();
}

/// The host refused every credential offered.
class SshAuthFailed implements Exception {
  const SshAuthFailed();
}

/// The SSH connection failed outside authentication: handshake, closed socket, timeout.
class SshConnectionFailed implements Exception {
  const SshConnectionFailed();
}

class ConnectTarget {
  const ConnectTarget({
    required this.hostId,
    required this.hostName,
    required this.address,
    required this.port,
    required this.user,
    this.identity,
  });

  final String hostId;
  final String hostName;
  final String address;
  final int port;
  final String user;
  final IdentitySecret? identity;
}

/// What the connection needs from the app: pins and the user's answers.
abstract interface class SshCallbacks {
  KnownHostMeta? pinnedKey(String hostId);
  Future<bool> confirmHostKey(HostKeyCheck check);
  Future<void> pinHostKey(String hostId, String keyType, String fingerprint);
  Future<String?> askPassword(String target);
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  );
}

abstract interface class SshShell {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  void write(Uint8List data);
  void resize(int cols, int rows);
  Future<void> get done;
  Future<void> close();
}

class SshConnector {
  SshConnector({Future<SSHSocket> Function(String host, int port)? openSocket})
    : _openSocket = openSocket ?? SSHSocket.connect;

  final Future<SSHSocket> Function(String host, int port) _openSocket;

  /// Never accepts a key on its own: an unknown or changed key needs the user's yes, then it is pinned.
  static Future<bool> verifyHostKey({
    required String hostId,
    required String hostName,
    required String keyType,
    required String fingerprint,
    required SshCallbacks callbacks,
  }) async {
    final pinned = callbacks.pinnedKey(hostId);
    final decision = decideHostKey(pinned, keyType, fingerprint);
    if (decision == HostKeyDecision.trusted) return true;
    final ok = await callbacks.confirmHostKey(
      HostKeyCheck(
        hostId: hostId,
        hostName: hostName,
        keyType: keyType,
        fingerprint: fingerprint,
        decision: decision,
        pinned: pinned,
      ),
    );
    if (!ok) return false; // no UI, a closed dialog or "no": refused
    await callbacks.pinHostKey(hostId, keyType, fingerprint);
    return true;
  }

  /// A shell with an 80×24 PTY over a direct connection.
  Future<SshShell> connect(
    ConnectTarget target,
    SshCallbacks callbacks,
  ) async => (await connectHop(target, callbacks)).shell();

  /// An authenticated connection, over [over] (the previous hop's forwarded channel) or direct TCP. A refused
  /// host key throws [HostKeyRejected]; dartssh2 errors, which are not [Exception]s, become [SshAuthFailed]
  /// or [SshConnectionFailed].
  Future<HopClient> connectHop(
    ConnectTarget target,
    SshCallbacks callbacks, {
    SSHSocket? over,
  }) async {
    final identity = target.identity;
    trace(
      TraceArea.ssh,
      'connect ${shortId(target.hostId)} port ${target.port}, auth ${identity?.kind.name ?? 'asked'}',
    );
    HostKeyDecision? refused;
    final client = SSHClient(
      over ?? await _openSocket(target.address, target.port),
      username: target.user,
      identities: identity?.kind == IdentityKind.privateKey
          ? SSHKeyPair.fromPem(identity!.privateKeyPem!, identity.passphrase)
          : null,
      onPasswordRequest: () {
        trace(TraceArea.ssh, 'server asks for a password');
        return identity?.kind == IdentityKind.password
            ? identity!.password
            : callbacks.askPassword('${target.user}@${target.hostName}');
      },
      onUserInfoRequest: (request) {
        trace(
          TraceArea.ssh,
          'keyboard-interactive: ${request.prompts.length} prompts',
        );
        return callbacks.answerPrompts(request.name, request.instruction, [
          for (final p in request.prompts) SshPrompt(p.promptText, p.echo),
        ]);
      },
      onVerifyHostKey: (type, fingerprintBytes) async {
        final fingerprint = utf8.decode(
          fingerprintBytes,
        ); // dartssh2 passes `SHA256:<base64>` as UTF-8
        final decision = decideHostKey(
          callbacks.pinnedKey(target.hostId),
          type,
          fingerprint,
        );
        final ok = await verifyHostKey(
          hostId: target.hostId,
          hostName: target.hostName,
          keyType: type,
          fingerprint: fingerprint,
          callbacks: callbacks,
        );
        trace(
          TraceArea.ssh,
          'host key $type: ${decision.name}${ok ? '' : ', refused'}',
        );
        if (!ok) refused = decision;
        return ok;
      },
    );
    try {
      await client.authenticated;
      return _DartSshHop(target.hostId, client);
    } catch (e) {
      trace(
        TraceArea.ssh,
        'connect ${shortId(target.hostId)} failed: ${e.runtimeType}',
      );
      await client.close();
      if (refused case final decision?) {
        throw HostKeyRejected(decision, hostId: target.hostId);
      }
      if (e is SSHAuthFailError) throw const SshAuthFailed();
      if (e is SSHError) throw const SshConnectionFailed();
      rethrow;
    }
  }
}

class _DartSshHop implements HopClient {
  _DartSshHop(this._hostId, this._client);

  final String _hostId;
  final SSHClient _client;

  @override
  Future<SSHSocket> forwardLocal(String host, int port) =>
      _client.forwardLocal(host, port);

  @override
  Future<SshShell> shell() async {
    try {
      final shell = _DartSshShell(
        _client,
        await _client.shell(pty: const SSHPtyConfig(width: 80, height: 24)),
      );
      trace(TraceArea.ssh, 'shell open ${shortId(_hostId)}');
      return shell;
    } on SSHError {
      await _client.close();
      throw const SshConnectionFailed();
    }
  }

  @override
  Future<void> close() async => _client.close();
}

class _DartSshShell implements SshShell {
  _DartSshShell(this._client, this._session);

  final SSHClient _client;
  final SSHSession _session;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void resize(int cols, int rows) => _session.resizeTerminal(cols, rows);

  @override
  Future<void> get done => _session.done;

  @override
  Future<void> close() async {
    _session.close();
    await _client.close();
  }
}
