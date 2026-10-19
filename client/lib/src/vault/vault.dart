// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../storage/local_mirror.dart';
import '../sync/ledger_store.dart';

enum EntryState { ok, unreadable, unsupported, readOnly }

/// One personal item as shown: [meta] is the opened payload, [pending] a local write not yet confirmed.
class VaultEntry {
  const VaultEntry(this.item, this.state, {this.meta, this.pending = false});

  final Item item;
  final EntryState state;
  final Map<String, Object?>? meta;
  final bool pending;

  String get id => item.id;
  String? get folderId => item.folderId;
  ItemKind get kind => item.kind;
  String? get name => switch (meta?['name']) {
    final String name => name,
    _ => null,
  };
}

/// The decrypted local view: server mirror rows overlaid by the outbox. Plaintext lives only in memory.
class Vault extends ChangeNotifier {
  Vault({
    required this.mirror,
    required this.ledger,
    required Future<void> Function(Item) write,
  }) : _send = write;

  final LocalMirror mirror;
  final LedgerStore ledger;
  final Future<void> Function(Item) _send;
  void Function(String id)? onReplay;
  Uint8List? _key;
  Map<String, VaultEntry> _entries = {};

  bool get isUnlocked => _key != null;

  /// The user key copy, for tests that seal items as another device would.
  @visibleForTesting
  Uint8List get debugKey => _requireKey();

  /// Returns the ledger result: false when the sealed ledger could not be opened (the caller reports it).
  Future<bool> unlock(Uint8List userKey) async {
    final key = _key = Uint8List.fromList(userKey);
    final ledgerOpened = await ledger.load(key);
    await reload();
    trace(
      TraceArea.vault,
      'unlocked, ledger ${ledgerOpened ? 'opened' : 'unreadable, reset'}',
    );
    return ledgerOpened;
  }

  void lock() {
    trace(TraceArea.vault, 'locked');
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    ledger.close();
    _entries = {};
    notifyListeners();
  }

  List<VaultEntry> get entries => List.unmodifiable(_entries.values);

  VaultEntry? entry(String id) => _entries[id];

  List<VaultEntry> ofKind(ItemKind kind) => [
    for (final e in _entries.values)
      if (e.kind == kind && !isTrashed(e.id)) e,
  ];

  /// Trashed: deleted, or a folder of its chain deleted (seen-set: a stored loop never hangs).
  bool isTrashed(String id) {
    final seen = <String>{};
    for (String? current = id; current != null && seen.add(current);) {
      final e = _entries[current];
      if (e == null) return false;
      if (e.item.deleted) return true;
      current = e.folderId;
    }
    return false;
  }

  Future<void> trashItem(String id) => _setDeleted(id, true);

  Future<void> restoreItem(String id) => _setDeleted(id, false);

  /// The subtree is trashed by definition: only the folder itself is written.
  Future<void> deleteFolder(String id) => trashItem(id);

  Future<String> saveFolder(
    FolderMeta meta, {
    String? id,
    String? parentId,
  }) async {
    final seen = <String>{};
    for (
      String? up = parentId;
      up != null && seen.add(up);
      up = _entries[up]?.folderId
    ) {
      if (up == id) {
        throw ArgumentError.value(
          parentId,
          'parentId',
          'is the folder itself or inside it',
        );
      }
    }
    return upsertItem(
      type: 'folder',
      id: id,
      folderId: parentId,
      meta: meta.toJson(),
    );
  }

  /// A rename is never a move: the entry keeps its folder. The secret kind must match the meta kind.
  Future<void> updateIdentity(
    String id,
    IdentityMeta meta, {
    IdentitySecret? secret,
  }) async {
    final current =
        _entries[id] ??
        (throw ArgumentError.value(id, 'id', 'unknown identity'));
    final kind = secret?.kind.name ?? current.meta?['kind'];
    if (kind != meta.kind.name) {
      throw ArgumentError(
        'identity kind ${meta.kind.name} does not match its secret ($kind)',
      );
    }
    await upsertItem(
      type: 'identity',
      id: id,
      folderId: current.folderId,
      meta: meta.toJson(),
      secret: secret?.toJson(),
    );
  }

  /// Null when unreadable, replayed or of another kind than its meta.
  Future<IdentitySecret?> identitySecret(String id) async {
    final e = _entries[id];
    if (e == null || e.state != EntryState.ok || e.kind != ItemKind.identity) {
      return null;
    }
    try {
      final json = await _secretJson(id);
      if (json == null) return null;
      final secret = IdentitySecret.fromJson(json);
      return secret.kind.name == e.meta?['kind'] ? secret : null;
    } on _ReplayedSecret {
      return null;
    } on DecryptionFailed {
      return null;
    } on UnsupportedEnvelope {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// The `ok` profile with the smallest id wins on every device; none → an empty profile.
  ProfileMeta get profile => switch (_profileEntry) {
    final VaultEntry e => ProfileMeta.fromJson(e.meta),
    null => ProfileMeta(),
  };

  /// Merges into the winning profile's prefs: null removes a key, unknown keys stay.
  Future<void> setPrefs(Map<String, Object?> changes) {
    final current = profile;
    final prefs = {...current.prefs};
    for (final MapEntry(:key, :value) in changes.entries) {
      value == null ? prefs.remove(key) : prefs[key] = value;
    }
    return _writeProfile(
      ProfileMeta(
        schemaVersion: current.schemaVersion,
        displayName: current.displayName,
        prefs: prefs,
        extra: current.extra,
      ),
    );
  }

  Future<void> setDisplayName(String? name) {
    final current = profile;
    return _writeProfile(
      ProfileMeta(
        schemaVersion: current.schemaVersion,
        displayName: name,
        prefs: current.prefs,
        extra: current.extra,
      ),
    );
  }

  /// A copy of [mine] under a new id at revision 0, name suffixed, secret re-sealed. Null for an unknown type.
  Future<Item?> conflictCopy(Item mine, {required String suffix}) async {
    if (mine.kind == ItemKind.unknown) return null;
    final meta = (await open(mine, PayloadPart.meta, fromServer: false))!.json;
    final secret = mine.secret == null
        ? null
        : (await open(mine, PayloadPart.secret, fromServer: false))!.json;
    if (meta['name'] case final String name) {
      final max = mine.kind == ItemKind.snippet
          ? PayloadLimits.snippetName
          : PayloadLimits.name;
      meta['name'] = String.fromCharCodes('$name$suffix'.runes.take(max));
    }
    return seal(
      id: newId(),
      type: mine.type,
      folderId: mine.folderId,
      meta: meta,
      secret: secret,
    );
  }

  /// The ledger pin wins over the synced item: a server cannot revert or delete a pin on this device.
  KnownHostMeta? trustedPin(String hostId) =>
      ledger.hostPin(hostId) ?? _knownHostMeta(_knownHostWinner(hostId));

  /// Ledger first (saved), then the winning knownHost item; read-only only skips the sync.
  Future<void> pinHostKey(
    String hostId,
    String keyType,
    String fingerprint,
  ) async {
    trace(TraceArea.vault, 'pin host key of ${shortId(hostId)}');
    final pin = KnownHostMeta(
      hostItemId: hostId,
      keyType: keyType,
      sha256Fingerprint: fingerprint,
    );
    await ledger.setHostPin(hostId, pin);
    try {
      await upsertItem(
        type: 'knownHost',
        id: _knownHostWinner(hostId)?.id,
        meta: pin.toJson(),
      );
    } on ReadOnlyException {
      // the local pin stands; the synced copy waits for a writable server
    }
  }

  /// First sight of a synced pin seeds the ledger; an existing ledger pin is never replaced from the server.
  Future<void> _seedPins() async {
    final synced = _knownHostWinners(_entries.values.where((e) => !e.pending));
    for (final MapEntry(key: host, value: winner) in synced.entries) {
      if (ledger.hostPin(host) == null) {
        await ledger.setHostPin(host, _knownHostMeta(winner)!);
      }
    }
  }

  VaultEntry? _knownHostWinner(String hostId) =>
      _knownHostWinners(_entries.values)[hostId];

  /// One knownHost per host: the `ok` entry with the smallest id wins.
  static Map<String, VaultEntry> _knownHostWinners(
    Iterable<VaultEntry> entries,
  ) {
    final winners = <String, VaultEntry>{};
    for (final e in entries) {
      if (e.kind != ItemKind.knownHost || e.state != EntryState.ok) continue;
      final host = _knownHostMeta(e)!.hostItemId;
      final best = winners[host];
      if (best == null || e.id.compareTo(best.id) < 0) winners[host] = e;
    }
    return winners;
  }

  static KnownHostMeta? _knownHostMeta(VaultEntry? e) =>
      e == null ? null : KnownHostMeta.fromJson(e.meta);

  ResolvedHost resolve(String hostId) => hostLookup(hostId)!.resolved;

  /// An `ok` host with its inherited values; null for anything else.
  ({HostMeta meta, ResolvedHost resolved, bool org})? hostLookup(String id) {
    final e = _entries[id];
    if (e == null || e.state != EntryState.ok || e.kind != ItemKind.host) {
      return null;
    }
    final meta = HostMeta.fromJson(e.meta);
    return (
      meta: meta,
      resolved: resolveHost(
        meta,
        e.folderId,
        _folderOf,
        hostId: id,
        parentOf: (f) => _entries[f]?.folderId,
      ),
      org: e.item.scope == ItemScope.org,
    );
  }

  FolderMeta? _folderOf(String id) {
    final f = _entries[id];
    return f != null && f.state == EntryState.ok && f.kind == ItemKind.folder
        ? FolderMeta.fromJson(f.meta)
        : null;
  }

  VaultEntry? get _profileEntry {
    final profiles = [
      for (final e in _entries.values)
        if (e.kind == ItemKind.profile && e.state == EntryState.ok) e,
    ]..sort((a, b) => a.id.compareTo(b.id));
    return profiles.firstOrNull;
  }

  Future<void> _writeProfile(ProfileMeta meta) =>
      upsertItem(type: 'profile', id: _profileEntry?.id, meta: meta.toJson());

  /// Same envelopes with `deleted` flipped: `deleted` is not in the AAD, so nothing is re-sealed; `secret: null` keeps it.
  Future<void> _setDeleted(String id, bool deleted) async {
    _requireKey();
    final current =
        _entries[id] ?? (throw ArgumentError.value(id, 'id', 'unknown item'));
    if (current.state != EntryState.ok) {
      throw StateError('${current.state.name} item is not rewritten');
    }
    final json = current.item.toJson()
      ..removeWhere((k, _) => _serverSet.contains(k))
      ..['deleted'] = deleted;
    if (!_queuedSecret(id)) {
      json['secret'] =
          null; // a queued secret not stored yet is sent again as is
    }
    await _write(Item.fromJson(json));
  }

  static const _serverSet = {
    'purged',
    'createdAt',
    'updatedAt',
    'updatedBy',
    'updatedDevice',
  };

  /// Opens one part. A server payload ([fromServer]) older than its mark is a replay: [onReplay], null.
  Future<OpenedPayload?> open(
    Item item,
    PayloadPart part, {
    bool fromServer = true,
  }) async {
    final key = _requireKey();
    final envelope = part == PayloadPart.meta ? item.meta : item.secret;
    if (envelope == null) {
      throw FormatException('item has no ${part.name} payload');
    }
    final opened = await PayloadCrypto.open(
      PayloadAad.of(item, part),
      envelope,
      key,
    );
    if (fromServer) {
      if (ledger.isReplay(item.id, part, opened.seq)) {
        onReplay?.call(item.id);
        return null;
      }
      if (opened.seq case final seq?) ledger.confirm(item.id, part, seq);
    }
    return opened;
  }

  Future<void> reload() async {
    final key = _key;
    if (key == null) {
      return; // locked: a late sync round finds nothing to rebuild
    }
    final queued = {for (final e in mirror.outbox()) e.item.id: e.item};
    final rows = {
      for (final i in mirror.items()) i.id: i,
      ...queued,
    }; // the outbox overlays the server row
    final next = <String, VaultEntry>{};
    for (final item in rows.values) {
      if (item.scope != ItemScope.personal || item.purged) {
        continue; // Org hook: org items are not read yet
      }
      final fromServer = !queued.containsKey(item.id);
      final built = await _build(item, fromServer: fromServer);
      final previous = _entries[item.id];
      next[item.id] =
          built ??
          (previous == null
              ? VaultEntry(item, EntryState.unreadable)
              : VaultEntry(
                  item,
                  previous.state,
                  meta: previous.meta,
                )); // replay: keep what was shown, take the new revision
    }
    _entries = next;
    if (tracing(TraceArea.vault)) {
      final odd = next.values.where((e) => e.state != EntryState.ok).length;
      trace(
        TraceArea.vault,
        'reload: ${next.length} entries, $odd not ok, outbox ${queued.length}',
      );
    }
    await _seedPins();
    await ledger.save();
    notifyListeners();
  }

  /// One seq for both parts, keyId `user`, the AAD of the new placement.
  Future<Item> seal({
    required String id,
    required String type,
    String? folderId,
    bool deleted = false,
    int revision = 0,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) async {
    final key = _requireKey();
    final seq = ledger.nextSeq(id);
    Future<Map<String, Object?>> sealPart(
      PayloadPart part,
      Map<String, Object?> json,
    ) async => (await PayloadCrypto.seal(
      PayloadAad(
        itemId: id,
        part: part,
        type: type,
        scope: ItemScope.personal,
        orgId: null,
        folderId: folderId,
      ),
      json,
      key,
      KeyIds.user,
      seq: seq,
    )).toJson();
    return Item.fromJson({
      'id': id,
      'type': type,
      'scope': 'personal',
      'orgId': null,
      'folderId': folderId,
      'schemaVersion': 1,
      'revision': revision,
      'deleted': deleted,
      'meta': await sealPart(PayloadPart.meta, meta),
      'secret': secret == null
          ? null
          : await sealPart(PayloadPart.secret, secret),
    });
  }

  Future<String> upsertItem({
    required String type,
    String? id,
    String? folderId,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) async {
    _requireKey();
    final current = id == null ? null : _entries[id];
    if (current != null && current.state != EntryState.ok) {
      throw StateError('${current.state.name} item is not rewritten');
    }
    final itemId = id ?? newId();
    // A move re-seals both parts (the server refuses a moved item without its secret), and so does an edit
    // of an item whose queued write still carries a secret the server has not stored yet.
    if (current != null &&
        secret == null &&
        (current.folderId != folderId || _queuedSecret(itemId))) {
      secret = await _secretJson(itemId);
    }
    final item = await seal(
      id: itemId,
      type: type,
      folderId: folderId,
      deleted: current?.item.deleted ?? false,
      revision: current?.item.revision ?? 0,
      meta: meta,
      secret: secret,
    );
    await _write(item);
    return itemId;
  }

  /// The current secret: the queued one if it carries a secret, else the server row's (each opened with its own AAD).
  Future<Map<String, Object?>?> _secretJson(String id) async {
    final queued = mirror
        .outbox()
        .where((e) => e.item.id == id)
        .firstOrNull
        ?.item;
    final holder = queued?.secret != null ? queued! : mirror.item(id);
    if (holder?.secret == null) return null;
    final opened = await open(
      holder!,
      PayloadPart.secret,
      fromServer: holder != queued,
    );
    if (opened == null) throw const _ReplayedSecret();
    return opened.json;
  }

  bool _queuedSecret(String id) =>
      mirror.outbox().any((e) => e.item.id == id && e.item.secret != null);

  Future<void> _write(Item item) async {
    trace(
      TraceArea.vault,
      'write ${item.type} ${shortId(item.id)}${item.deleted ? ' (trash)' : ''}',
    );
    await _send(item);
    await reload();
  }

  Uint8List _requireKey() => _key ?? (throw StateError('locked'));

  /// null = replayed payload.
  Future<VaultEntry?> _build(Item item, {required bool fromServer}) async {
    if (item.kind == ItemKind.unknown) {
      return VaultEntry(item, EntryState.unsupported, pending: !fromServer);
    }
    try {
      final opened = await open(item, PayloadPart.meta, fromServer: fromServer);
      if (opened == null) return null;
      final schema = opened.json['schemaVersion'];
      if (schema is int && schema > Payload.knownSchemaVersion) {
        return VaultEntry(
          item,
          EntryState.readOnly,
          meta: opened.json,
          pending: !fromServer,
        ); // never rewritten
      }
      _parse(
        item.kind,
        opened.json,
      ); // typed model: FormatException on a bad payload
      return VaultEntry(
        item,
        EntryState.ok,
        meta: opened.json,
        pending: !fromServer,
      );
    } on DecryptionFailed {
      return VaultEntry(item, EntryState.unreadable, pending: !fromServer);
    } on UnsupportedEnvelope {
      return VaultEntry(item, EntryState.unreadable, pending: !fromServer);
    } on FormatException {
      return VaultEntry(item, EntryState.unreadable, pending: !fromServer);
    }
  }

  static void _parse(ItemKind kind, Map<String, Object?> json) =>
      switch (kind) {
        ItemKind.host => HostMeta.fromJson(json),
        ItemKind.identity => IdentityMeta.fromJson(json),
        ItemKind.folder => FolderMeta.fromJson(json),
        ItemKind.snippet => SnippetMeta.fromJson(json),
        ItemKind.knownHost => KnownHostMeta.fromJson(json),
        ItemKind.profile => ProfileMeta.fromJson(json),
        ItemKind.hostBinding => HostBindingMeta.fromJson(json),
        ItemKind.memberPin => MemberPinMeta.fromJson(json),
        ItemKind.unknown => null,
      };
}

class _ReplayedSecret implements Exception {
  const _ReplayedSecret();
}
