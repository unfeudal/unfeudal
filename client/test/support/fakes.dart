// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/session/biometrics.dart';
import 'package:unfeudal_client/src/session/session_store.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/ssh/connections.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/ledger_store.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'sync_harness.dart';

final testUserId = newId();
final testDeviceId = newId();

Envelope fakeEnvelope([String keyId = 'user']) => Envelope.fromJson({
  'v': 1,
  'alg': 'xchacha20poly1305',
  'keyId': keyId,
  'nonce': b64(Uint8List(24)),
  'ct': b64(Uint8List(16)),
});

/// A wire item whose payloads are not meant to be opened (mirror and engine tests).
Item wireItem(
  String id, {
  int revision = 1,
  String type = 'host',
  bool deleted = false,
  bool purged = false,
  String? folderId,
  String? updatedDevice,
}) => Item.fromJson({
  'id': id,
  'type': type,
  'scope': 'personal',
  'orgId': null,
  'folderId': folderId,
  'schemaVersion': 1,
  'revision': revision,
  'deleted': deleted || purged,
  if (purged) 'purged': true,
  'meta': purged ? null : fakeEnvelope().toJson(),
  'secret': null,
  'createdAt': iso(DateTime.utc(2026, 10)),
  'updatedAt': iso(DateTime.utc(2026, 10, 14)),
  'updatedBy': testUserId,
  'updatedDevice': updatedDevice ?? testDeviceId,
});

/// A personal item sealed as another device (or the server) holds it.
Future<Item> sealItem(
  Uint8List key, {
  String? id,
  String type = 'host',
  String? folderId,
  required Map<String, Object?> meta,
  Map<String, Object?>? secret,
  int seq = 1,
  int revision = 1,
  bool deleted = false,
  DateTime? createdAt,
}) async {
  final itemId = id ?? newId();
  PayloadAad aad(PayloadPart p) => PayloadAad(
    itemId: itemId,
    part: p,
    type: type,
    scope: ItemScope.personal,
    orgId: null,
    folderId: folderId,
  );
  return Item.fromJson({
    'id': itemId,
    'type': type,
    'scope': 'personal',
    'orgId': null,
    'folderId': folderId,
    'schemaVersion': 1,
    'revision': revision,
    'deleted': deleted,
    'meta': (await PayloadCrypto.seal(
      aad(PayloadPart.meta),
      meta,
      key,
      keyId: KeyIds.user,
      seq: seq,
    )).toJson(),
    'secret': secret == null
        ? null
        : (await PayloadCrypto.seal(
            aad(PayloadPart.secret),
            secret,
            key,
            keyId: KeyIds.user,
            seq: seq,
          )).toJson(),
    'createdAt': iso(createdAt ?? DateTime.utc(2026, 10, 14)),
    'updatedAt': iso(DateTime.utc(2026, 10, 14)),
    'updatedBy': testUserId,
    'updatedDevice': newId(),
  });
}

Map<String, Object?> hostJson(
  String name, {
  String address = '10.0.0.5',
  int? port,
  String? user,
  String? identityId,
  List<String> tags = const [],
}) => {
  'schemaVersion': 1,
  'name': name,
  'address': address,
  'port': ?port,
  'user': user,
  'identityId': identityId,
  'tags': tags,
  'notes': null,
  'startupCommand': null,
};

Map<String, Object?> folderJson(
  String name, {
  int? port,
  String? user,
  String? identityId,
}) => {
  'schemaVersion': 1,
  'name': name,
  'defaults': {'port': port, 'user': user, 'identityId': identityId},
};

/// Vault over [mirror] whose writes go straight to the outbox.
Future<Vault> testVault(Uint8List key, LocalMirror mirror) async {
  final v = Vault(
    mirror: mirror,
    ledger: LedgerStore(mirror),
    write: (items) async => mirror.enqueueAll(items),
  );
  await v.unlock(key);
  return v;
}

/// The server accepts every queued write as-is.
List<Item> confirmOutbox(LocalMirror m) => [
  for (final e in m.outbox())
    () {
      final stored = Item.fromJson(
        e.item.toJson()
          ..['revision'] = e.baseRevision + 1
          ..['createdAt'] = iso(
            m.item(e.item.id)?.createdAt ?? DateTime.utc(2026, 10, 15),
          )
          ..['updatedAt'] = iso(DateTime.utc(2026, 10, 15))
          ..['updatedBy'] = testUserId
          ..['updatedDevice'] = testDeviceId,
      );
      m
        ..upsertItems([stored])
        ..removeOutbox(e.item.id);
      return stored;
    }(),
];

class FakeClock {
  FakeClock([DateTime? t]) : value = t ?? DateTime.utc(2026, 10, 15, 12);
  DateTime value;
  DateTime now() => value;
  void advance(Duration d) => value = value.add(d);
}

/// Settings in memory: [load] returns the last value saved.
class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this.saved = const Settings()]);
  Settings saved;

  @override
  Future<Settings> load() async => saved;

  @override
  Future<void> save(Settings settings) async => saved = settings;
}

class FakeSecureKv implements SecureKv {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Runs the real host-key check against a fixed key, then hands out [FakeShell]s.
class FakeSshConnector extends SshConnector {
  String keyType = 'ssh-ed25519';
  String fingerprint = 'SHA256:${'A' * 43}';
  Exception? failWith;
  final targets = <ConnectTarget>[];
  final shells = <FakeShell>[];
  final hops = <FakeHop>[];

  @override
  Future<HopClient> connectHop(
    ConnectTarget target,
    SshCallbacks callbacks, {
    SSHSocket? over,
  }) async {
    targets.add(target);
    if (failWith case final error?) throw error;
    final (:accepted, :decision) = await SshConnector.verifyHostKey(
      hostId: target.hostId,
      hostName: target.hostName,
      keyType: keyType,
      fingerprint: fingerprint,
      callbacks: callbacks,
    );
    if (!accepted) throw HostKeyRejected(decision, hostId: target.hostId);
    final hop = FakeHop(target.hostId, shells);
    hops.add(hop);
    return hop;
  }
}

/// Host pins by host id; [answer] to every host-key question, [password] and [promptAnswer] to the server.
class FakeSshCallbacks implements SshCallbacks {
  FakeSshCallbacks({this.answer = false, this.password, this.promptAnswer});
  bool answer;
  final String? password;
  final String? promptAnswer;
  final pins = <String, KnownHostMeta>{};
  final asked = <HostKeyCheck>[];
  final prompts = <SshPrompt>[];

  @override
  KnownHostMeta? pinnedKey(String hostId) => pins[hostId];

  @override
  Future<bool> confirmHostKey(HostKeyCheck check) async {
    asked.add(check);
    return answer;
  }

  @override
  Future<void> pinHostKey(
    String hostId,
    String keyType,
    String fingerprint,
  ) async => pins[hostId] = KnownHostMeta(
    hostItemId: hostId,
    keyType: keyType,
    sha256Fingerprint: fingerprint,
  );

  @override
  Future<String?> askPassword(String target) async => password;

  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async {
    this.prompts.addAll(prompts);
    return promptAnswer == null
        ? null
        : [for (final _ in prompts) promptAnswer!];
  }
}

/// A forwarded channel that carries nothing.
class FakeChannel implements SSHSocket {
  FakeChannel([this.label]);

  final String? label;
  final _in = StreamController<Uint8List>();
  final _out = StreamController<List<int>>();

  @override
  Stream<Uint8List> get stream => _in.stream;

  @override
  StreamSink<List<int>> get sink => _out.sink;

  @override
  Future<void> get done => _out.done;

  @override
  Future<void> close() async {
    await _in.close();
    await _out.close();
  }

  @override
  void destroy() => close();

  @override
  Future<void> flush() async {}
}

class FakeHop implements HopClient {
  FakeHop(this.hostId, this.shells);

  final String hostId;
  final List<FakeShell> shells;
  final forwarded = <String>[];
  bool closed = false;

  @override
  Future<SSHSocket> forwardLocal(String host, int port) async {
    forwarded.add('$host:$port');
    return FakeChannel('$hostId>$host');
  }

  @override
  Future<SshShell> shell() async {
    final shell = FakeShell();
    shells.add(shell);
    return shell;
  }

  @override
  Future<void> close() async => closed = true;
}

/// A loopback port that was free a moment ago.
Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

class FakeShell implements SshShell {
  final _stdout = StreamController<Uint8List>.broadcast();
  final _done = Completer<void>();
  final written = <Uint8List>[];
  final sizes = <(int, int)>[];
  bool closed = false;

  void emit(String text) => _stdout.add(utf8.encode(text));

  void hangUp() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  void write(Uint8List data) => written.add(data);

  @override
  void resize(int cols, int rows) => sizes.add((cols, rows));

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    closed = true;
    hangUp();
  }
}

/// AppState over the harness, in memory, real crypto at KdfParams.testing.
AppState testAppState({
  SyncHarness? harness,
  Settings settings = const Settings(),
  FakeSecureKv? kv,
  Map<String, LocalMirror>? mirrors,
  SshConnector? ssh,
  SettingsStore? settingsStore,
  LoquetMemory? loquetMemory,
  DateTime Function()? loquetClock,
  BiometricBackend? biometrics,
}) {
  final h = harness ?? SyncHarness();
  final m = mirrors ?? <String, LocalMirror>{};
  return AppState(
    sessions: SessionStore(kv ?? FakeSecureKv()),
    settingsStore: settingsStore ?? FakeSettingsStore(settings),
    openMirror: (userId) async => m[userId] ??= LocalMirror.inMemory(),
    httpClient: h.client,
    ssh: ssh ?? FakeSshConnector(),

    kdfFloor: KdfParams.testing,
    kdf: KdfParams.testing,
    loquetMemory: loquetMemory,
    // a Thursday noon: no suite depends on the machine's hour, weekday or calendar
    loquetClock: loquetClock ?? () => DateTime(2026, 10, 15, 12),
    biometrics: biometrics,
  );
}

class FakeDialogs implements SshDialogs {
  bool accept = false;
  String? password;
  bool runStartup = false;
  final checks = <HostKeyCheck>[];
  final startupAsked = <String>[];

  @override
  Future<bool> confirmHostKey(HostKeyCheck check) async {
    checks.add(check);
    return accept;
  }

  @override
  Future<bool> confirmStartupCommand(String hostName, String command) async {
    startupAsked.add(command);
    return runStartup;
  }

  @override
  Future<String?> askPassword(String target) async => password;

  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async => null;
}

class FakeBiometricBackend implements BiometricBackend {
  FakeBiometricBackend({this.isAvailable = true});
  bool isAvailable;
  bool cancel = false;
  Uint8List? secretBytes; // the "hardware" secret
  int deleted = 0;
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<Uint8List?> secret({
    required bool create,
    required String reason,
  }) async {
    if (cancel || !isAvailable) return null;
    if (create) secretBytes ??= SymmetricCipher.newKey();
    return secretBytes;
  }

  @override
  Future<void> delete() async {
    deleted++;
    secretBytes = null;
  }
}
