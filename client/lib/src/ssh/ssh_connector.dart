// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

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

/// OpenSSH form: `SHA256:` + unpadded base64 of the SHA-256 of the key blob.
String sshFingerprint(Uint8List blob) =>
    'SHA256:${base64.encode(SHA256Digest().process(blob)).replaceAll('=', '')}';

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
  const HostKeyRejected(this.decision);
  final HostKeyDecision decision;

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

  /// A shell with an 80×24 PTY. A refused host key throws [HostKeyRejected].
  Future<SshShell> connect(ConnectTarget target, SshCallbacks callbacks) async {
    final identity = target.identity;
    HostKeyDecision? refused;
    final client = SSHClient(
      await _openSocket(target.address, target.port),
      username: target.user,
      identities: identity?.kind == IdentityKind.privateKey
          ? SSHKeyPair.fromPem(identity!.privateKeyPem!, identity.passphrase)
          : null,
      onPasswordRequest: () => identity?.kind == IdentityKind.password
          ? identity!.password
          : callbacks.askPassword('${target.user}@${target.hostName}'),
      onUserInfoRequest: (request) => callbacks.answerPrompts(
        request.name,
        request.instruction,
        [for (final p in request.prompts) SshPrompt(p.promptText, p.echo)],
      ),
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
        if (!ok) refused = decision;
        return ok;
      },
    );
    try {
      return _DartSshShell(
        client,
        await client.shell(pty: const SSHPtyConfig(width: 80, height: 24)),
      );
    } catch (_) {
      await client.close();
      if (refused case final decision?) throw HostKeyRejected(decision);
      rethrow;
    }
  }
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
