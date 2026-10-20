// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../debug_trace.dart';
import '../orgs/folder_keyring.dart';
import '../storage/local_mirror.dart';
import '../storage/sealed_kv.dart';
import '../sync/ledger_store.dart';
import 'item_rewrite.dart';

enum EntryState { ok, unreadable, unsupported, readOnly }

/// One item as shown: [meta] is the opened payload, [pending] a local write not yet confirmed,
/// [awaitingKey] an org item whose folder key version is not held.
class VaultEntry {
  const VaultEntry(
    this.item,
    this.state, {
    this.meta,
    this.pending = false,
    this.awaitingKey = false,
  });

  final Item item;
  final EntryState state;
  final Map<String, Object?>? meta;
  final bool pending;
  final bool awaitingKey;

  String get id => item.id;
  String? get orgId => item.orgId;
  String? get folderId => item.folderId;
  ItemKind get kind => item.kind;
  String? get name => switch (meta?['name']) {
    final String name => name,
    _ => null,
  };
}

/// What a rewrite depends on its scope: who may write, how the current parts open, which keys seal.
abstract interface class WriteScope {
  /// Throws unless [current] (null: a new item) may be written as [type] in [orgId]'s [folderId].
  void checkWrite(
    VaultEntry? current, {
    required String type,
    required String? orgId,
    required String? folderId,
  });

  /// Throws unless [current] may be trashed or restored.
  void checkDelete(VaultEntry current);

  /// The plaintext of [part]; a [fromServer] part is replay-checked where the scope does it.
  Future<Map<String, Object?>> openPart(
    Item item,
    PayloadPart part, {
    required bool fromServer,
  });

  /// The key and keyId sealing each part of item [id] in [folderId]; throws when one is not held.
  SealKeys sealKeys({
    required String type,
    required String id,
    required String? folderId,
    required bool withSecret,
  });
}

/// Orders entries by name, unnamed ones first.
int byName(VaultEntry a, VaultEntry b) =>
    (a.name ?? '').compareTo(b.name ?? '');

/// The decrypted local view: server mirror rows overlaid by the outbox. Plaintext lives only in memory.
class Vault extends ChangeNotifier {
  Vault({
    required this.mirror,
    required this.ledger,
    required Future<void> Function(Item) write,
  }) : _send = write {
    _personal = _PersonalScope(this);
  }

  final LocalMirror mirror;
  final LedgerStore ledger;
  final Future<void> Function(Item) _send;
  late final WriteScope _personal;
  void Function(String id)? onReplay;

  /// Set at unlock by the org controller, null at lock; without it org items stay hidden.
  FolderKeyring? keyring;
  Uint8List? _key;
  Map<String, VaultEntry> _entries = {};

  // Ids whose server payload was a replay at the last reload: checked again at the next.
  Set<String> _replayed = {};

  // Counts the entries written in place, so a reload that read the mirror before one starts over.
  int _writes = 0;

  /// The winning knownHost of each host, rebuilt at each reload.
  Map<String, ({String id, KnownHostMeta meta})> _knownHosts = {};

  bool get isUnlocked => _key != null;

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
    _replayed = {};
    _knownHosts = {};
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

  Future<void> trashItem(String id) async {
    _requireKey();
    await setDeleted(_personal, id, deleted: true);
  }

  Future<void> restoreItem(String id) async {
    _requireKey();
    await setDeleted(_personal, id, deleted: false);
  }

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

  /// Null when unreadable, replayed or of another kind than its meta.
  Future<IdentitySecret?> identitySecret(String id) async {
    final e = _entries[id];
    if (e == null || e.state != EntryState.ok || e.kind != ItemKind.identity) {
      return null;
    }
    try {
      final json = await _currentSecret(_personal, id);
      if (json == null) return null;
      final secret = IdentitySecret.fromJson(json);
      return secret.kind.name == e.meta?['kind'] ? secret : null;
    } on _ReplayedSecret {
      return null;
    } on Exception catch (e) {
      if (!isUnreadable(e)) rethrow;
      return null;
    }
  }

  /// The `ok` profile with the smallest id wins on every device; with none, an empty profile.
  ProfileMeta get profile => switch (_profileEntry) {
    final VaultEntry e => ProfileMeta.fromJson(e.meta),
    null => ProfileMeta(),
  };

  /// Merges into the winning profile's prefs: null removes a key, unknown keys stay.
  Future<void> setPrefs(Map<String, Object?> changes) {
    final prefs = {...profile.prefs};
    for (final MapEntry(:key, :value) in changes.entries) {
      value == null ? prefs.remove(key) : prefs[key] = value;
    }
    return _updateProfile(displayName: profile.displayName, prefs: prefs);
  }

  Future<void> setDisplayName(String? name) =>
      _updateProfile(displayName: name, prefs: profile.prefs);

  /// A personal copy of [mine] under a new id at revision 0, name suffixed, secret re-sealed; an org item's
  /// copy leaves its org folder. Null for an unknown type.
  Future<Item?> conflictCopy(Item mine, {required String suffix}) =>
      conflictCopyIn(
        _personal,
        mine,
        suffix: suffix,
        folderId: mine.scope == ItemScope.personal ? mine.folderId : null,
      );

  /// A copy of [mine] in [orgId]'s [folderId] under a new id at revision 0, both parts opened and sealed
  /// by [scope], the name suffixed. Null for an unknown type.
  Future<Item?> conflictCopyIn(
    WriteScope scope,
    Item mine, {
    required String suffix,
    String? orgId,
    String? folderId,
  }) async {
    final parts = await conflictCopyParts(
      mine,
      suffix,
      (part) => scope.openPart(mine, part, fromServer: false),
    );
    if (parts == null) return null;
    final id = newId();
    return sealItem(
      id: id,
      type: mine.type,
      orgId: orgId,
      folderId: folderId,
      meta: parts.meta,
      secret: parts.secret,
      keyFor: scope.sealKeys(
        type: mine.type,
        id: id,
        folderId: folderId,
        withSecret: parts.secret != null,
      ),
    );
  }

  /// The ledger pin wins over the synced item: a server cannot revert or delete a pin on this device.
  KnownHostMeta? trustedPin(String hostId) =>
      ledger.hostPin(hostId) ?? _knownHosts[hostId]?.meta;

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
        id: _knownHosts[hostId]?.id,
        meta: pin.toJson(),
      );
    } on ReadOnlyException {
      // the local pin stands; the synced copy waits for a writable server
    }
  }

  // First sight of a synced pin seeds the ledger; an existing ledger pin is never replaced from the server.
  Future<void> _seedPins() async {
    final synced = _knownHostWinners(_entries.values.where((e) => !e.pending));
    for (final MapEntry(key: host, value: pin) in synced.entries) {
      if (ledger.hostPin(host) != null) continue;
      await ledger.setHostPin(host, pin.meta);
    }
  }

  /// One knownHost per host: the [winner] among the entries naming it.
  static Map<String, ({String id, KnownHostMeta meta})> _knownHostWinners(
    Iterable<VaultEntry> entries,
  ) {
    final byHost = <String, List<VaultEntry>>{};
    for (final e in entries) {
      if (e.kind != ItemKind.knownHost || e.state != EntryState.ok) continue;
      byHost
          .putIfAbsent(KnownHostMeta.fromJson(e.meta).hostItemId, () => [])
          .add(e);
    }
    return {
      for (final MapEntry(key: host, value: named) in byHost.entries)
        if (winner(named) case final w?)
          host: (id: w.id, meta: KnownHostMeta.fromJson(w.meta)),
    };
  }

  /// The personal `ok` entry with the smallest id among [entries] that pass [where]: the same on every device.
  static VaultEntry? winner(
    Iterable<VaultEntry> entries, [
    bool Function(VaultEntry e)? where,
  ]) {
    VaultEntry? best;
    for (final e in entries) {
      if (e.state != EntryState.ok || e.orgId != null) continue;
      if (where != null && !where(e)) continue;
      if (best == null || e.id.compareTo(best.id) < 0) best = e;
    }
    return best;
  }

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

  VaultEntry? get _profileEntry =>
      winner(_entries.values.where((e) => e.kind == ItemKind.profile));

  Future<void> _updateProfile({
    required String? displayName,
    required Map<String, Object?> prefs,
  }) {
    final current = profile;
    final meta = ProfileMeta(
      schemaVersion: current.schemaVersion,
      displayName: displayName,
      prefs: prefs,
      extra: current.extra,
    );
    return upsertItem(
      type: 'profile',
      id: _profileEntry?.id,
      meta: meta.toJson(),
    );
  }

  /// Flips `deleted` on [id] once [scope] allows it; nothing is re-sealed.
  Future<void> setDeleted(
    WriteScope scope,
    String id, {
    required bool deleted,
  }) async {
    final current =
        _entries[id] ?? (throw ArgumentError.value(id, 'id', 'unknown item'));
    scope.checkDelete(current);
    await _write(withDeleted(mirror, current.item, deleted), current.meta!);
  }

  /// Opens one part. A server payload ([fromServer]) older than its mark is a replay: [onReplay], null.
  Future<OpenedPayload?> open(
    Item item,
    PayloadPart part, {
    bool fromServer = true,
  }) async {
    _requireKey();
    final envelope = part == PayloadPart.meta ? item.meta : item.secret;
    if (envelope == null) {
      throw FormatException('item has no ${part.name} payload');
    }
    final key =
        _keyFor(item, envelope, part) ?? (throw const _MissingFolderKey());
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

  // The user key for personal items, else the keyring's; null when not held (the entry shows awaitingKey).
  Uint8List? _keyFor(Item item, Envelope envelope, PayloadPart part) =>
      item.scope == ItemScope.personal
      ? _key
      : folderPartKey(keyring, envelope, part);

  Future<void> reload() async {
    final key = _key;
    if (key == null) {
      return; // locked: a late sync round finds nothing to rebuild
    }
    final writes = _writes;
    final queued = {for (final e in mirror.outbox()) e.item.id: e.item};
    // The outbox overlays the server row.
    final rows = {for (final i in mirror.items()) i.id: i, ...queued};
    final next = <String, VaultEntry>{};
    final replayed = <String>{};
    for (final item in rows.values) {
      if (_key == null) return; // locked while this round ran
      if (item.purged || (item.scope == ItemScope.org && keyring == null)) {
        continue;
      }
      final fromServer = !queued.containsKey(item.id);
      final previous = _entries[item.id];
      if (_reusable(previous, item, pending: !fromServer)) {
        next[item.id] = VaultEntry(
          item,
          previous!.state,
          meta: previous.meta,
          pending: previous.pending,
        );
        continue;
      }
      final built = await _build(item, fromServer: fromServer);
      if (built == null) replayed.add(item.id);
      // A replay keeps what was shown and takes the new revision.
      next[item.id] =
          built ??
          (previous == null
              ? VaultEntry(item, EntryState.unreadable)
              : VaultEntry(item, previous.state, meta: previous.meta));
    }
    if (_writes != writes) return reload();
    _entries = next;
    _replayed = replayed;
    _knownHosts = _knownHostWinners(next.values);
    if (tracing(TraceArea.vault)) {
      final odd = next.values.where((e) => e.state != EntryState.ok).length;
      trace(
        TraceArea.vault,
        'reload: ${next.length} entries, $odd not ok, outbox ${queued.length}',
      );
    }
    await _seedPins();
    await ledger.saveIfChanged();
    notifyListeners();
  }

  // previous still shows item: same placement (the AAD) and meta envelope, same pending state, opened, not a
  // replay; a server row only while its mark stands (a restore empties the marks, so every row is checked again).
  bool _reusable(VaultEntry? previous, Item item, {required bool pending}) =>
      previous != null &&
      previous.pending == pending &&
      previous.state != EntryState.unreadable &&
      !_replayed.contains(item.id) &&
      (pending || ledger.mark(item.id, PayloadPart.meta) > 0) &&
      previous.item.type == item.type &&
      previous.item.scope == item.scope &&
      previous.item.orgId == item.orgId &&
      previous.item.folderId == item.folderId &&
      jsonEncode(previous.item.meta?.toJson()) ==
          jsonEncode(item.meta?.toJson());

  /// One seq for both parts, keyId `user`, the AAD of the new placement.
  Future<Item> seal({
    required String id,
    required String type,
    String? folderId,
    bool deleted = false,
    int revision = 0,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) => sealItem(
    id: id,
    type: type,
    folderId: folderId,
    deleted: deleted,
    revision: revision,
    meta: meta,
    secret: secret,
    keyFor: _personal.sealKeys(
      type: type,
      id: id,
      folderId: folderId,
      withSecret: secret != null,
    ),
  );

  /// Both parts sealed by [keyFor] with the next seq of [id], keeping what the current item carries.
  Future<Item> sealItem({
    required String id,
    required String type,
    String? orgId,
    String? folderId,
    bool deleted = false,
    int revision = 0,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
    required SealKeys keyFor,
  }) => sealPayloads(
    current: _entries[id]?.item,
    id: id,
    type: type,
    orgId: orgId,
    folderId: folderId,
    deleted: deleted,
    revision: revision,
    seq: ledger.nextSeq(id),
    meta: meta,
    secret: secret,
    keyFor: keyFor,
  );

  Future<String> upsertItem({
    required String type,
    String? id,
    String? folderId,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) => rewrite(
    _personal,
    type: type,
    id: id,
    folderId: folderId,
    meta: meta,
    secret: secret,
  );

  /// Writes [id] (null: a new item) once [scope] allows it; a move or an unsent secret re-seals the current secret.
  Future<String> rewrite(
    WriteScope scope, {
    required String type,
    String? id,
    String? orgId,
    String? folderId,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) async {
    final current = id == null ? null : _entries[id];
    scope.checkWrite(current, type: type, orgId: orgId, folderId: folderId);
    final itemId = id ?? newId();
    if (current != null &&
        secret == null &&
        resealsSecret(mirror, current.item, folderId)) {
      secret = await _currentSecret(scope, itemId);
    }
    final item = await sealItem(
      id: itemId,
      type: type,
      orgId: orgId,
      folderId: folderId,
      deleted: current?.item.deleted ?? false,
      revision: current?.item.revision ?? 0,
      meta: meta,
      secret: secret,
      keyFor: scope.sealKeys(
        type: type,
        id: itemId,
        folderId: folderId,
        withSecret: secret != null,
      ),
    );
    await _write(item, meta);
    return itemId;
  }

  // The current secret: the queued one if it carries a secret, else the server row's (each opened with its own AAD).
  Future<Map<String, Object?>?> _currentSecret(
    WriteScope scope,
    String id,
  ) async {
    final holder = secretHolder(mirror, id);
    if (holder == null) return null;
    return scope.openPart(
      holder.item,
      PayloadPart.secret,
      fromServer: !holder.queued,
    );
  }

  /// Hands [item] to the outbox without touching the entries (rotation reloads once, after the last).
  Future<void> send(Item item) => _send(item);

  // Sends item and shows it from meta, its plaintext in hand; the sync round reloads what else changed.
  Future<void> _write(Item item, Map<String, Object?> meta) async {
    trace(
      TraceArea.vault,
      'write ${item.type} ${shortId(item.id)}${item.deleted ? ' (trash)' : ''}',
    );
    await _send(item);
    if (_key == null) return; // locked while sending
    if (item.scope == ItemScope.org && keyring == null) return;
    _entries[item.id] = _written(item, meta);
    _writes++;
    _knownHosts = _knownHostWinners(_entries.values);
    await ledger.saveIfChanged();
    notifyListeners();
  }

  // The entry a reload would build for the queued item sealed from meta.
  VaultEntry _written(Item item, Map<String, Object?> meta) {
    if (item.kind == ItemKind.unknown) {
      return VaultEntry(item, EntryState.unsupported, pending: true);
    }
    try {
      final json = jsonDecode(jsonEncode(meta)) as Map<String, Object?>;
      return _entryOf(item, json, pending: true);
    } on FormatException {
      return VaultEntry(item, EntryState.unreadable, pending: true);
    }
  }

  Uint8List _requireKey() => _key ?? (throw StateError('locked'));

  static void _rewritable(VaultEntry e) {
    if (e.orgId != null) throw StateError('org items go through OrgWriter');
    if (e.state != EntryState.ok) {
      throw StateError('${e.state.name} item is not rewritten');
    }
  }

  // Null for a replayed payload.
  Future<VaultEntry?> _build(Item item, {required bool fromServer}) async {
    if (item.kind == ItemKind.unknown) {
      return VaultEntry(item, EntryState.unsupported, pending: !fromServer);
    }
    try {
      final opened = await open(item, PayloadPart.meta, fromServer: fromServer);
      if (opened == null) return null;
      return _entryOf(item, opened.json, pending: !fromServer);
    } on _MissingFolderKey {
      return VaultEntry(
        item,
        EntryState.unreadable,
        pending: !fromServer,
        awaitingKey: true,
      );
    } on Exception catch (e) {
      if (!isUnreadable(e)) rethrow;
      return VaultEntry(item, EntryState.unreadable, pending: !fromServer);
    }
  }

  // ok, or readOnly for a newer schema; FormatException on a bad payload.
  static VaultEntry _entryOf(
    Item item,
    Map<String, Object?> json, {
    required bool pending,
  }) {
    final schema = json['schemaVersion'];
    // A newer schema is shown but never rewritten.
    if (schema is int && schema > Payload.knownSchemaVersion) {
      return VaultEntry(
        item,
        EntryState.readOnly,
        meta: json,
        pending: pending,
      );
    }
    _parse(item.kind, json); // typed model: FormatException on a bad payload
    return VaultEntry(item, EntryState.ok, meta: json, pending: pending);
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

// Personal items: the user key, no permission check, replay-checked opens.
class _PersonalScope implements WriteScope {
  _PersonalScope(this._vault);
  final Vault _vault;

  @override
  void checkWrite(
    VaultEntry? current, {
    required String type,
    required String? orgId,
    required String? folderId,
  }) {
    _vault._requireKey();
    if (current != null) Vault._rewritable(current);
  }

  @override
  void checkDelete(VaultEntry current) => Vault._rewritable(current);

  @override
  Future<Map<String, Object?>> openPart(
    Item item,
    PayloadPart part, {
    required bool fromServer,
  }) async {
    final opened = await _vault.open(item, part, fromServer: fromServer);
    if (opened == null) throw const _ReplayedSecret();
    return opened.json;
  }

  @override
  SealKeys sealKeys({
    required String type,
    required String id,
    required String? folderId,
    required bool withSecret,
  }) {
    final key = _vault._requireKey();
    return (_) => (key: key, keyId: KeyIds.user);
  }
}

class _ReplayedSecret implements Exception {
  const _ReplayedSecret();
}

class _MissingFolderKey implements Exception {
  const _MissingFolderKey();
}
