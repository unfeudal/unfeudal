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

part 'editor_choices.dart';
part 'entry_rules.dart';
part 'host_key_pins.dart';
part 'item_sealer.dart';
part 'personal_scope.dart';
part 'synced_profile.dart';
part 'vault_entry.dart';

/// The decrypted local view: server mirror rows overlaid by the outbox. Plaintext lives only in memory.
class Vault extends ChangeNotifier {
  Vault({required this.mirror, required this.ledger, required this._send}) {
    _personal = _PersonalScope(this);
  }

  final LocalMirror mirror;
  final LedgerStore ledger;
  final Future<void> Function(List<Item>) _send;
  late final WriteScope _personal;
  late final hostKeys = HostKeyPins._(this);
  late final sealer = ItemSealer._(this);
  late final profile = SyncedProfile._(this);
  void Function(String id)? onReplay;

  /// Set at unlock by the org controller, null at lock; without it org items stay hidden.
  FolderKeyring? keyring;
  Uint8List? _key;
  Map<String, VaultEntry> _entries = {};

  // Ids whose server payload was a replay at the last reload: checked again at the next.
  Set<String> _replayed = {};

  // Counts the entries written in place, so a reload that read the mirror before one starts over.
  int _writes = 0;

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
    hostKeys._rebuild(const []);
    notifyListeners();
  }

  List<VaultEntry> get entries => List.unmodifiable(_entries.values);

  VaultEntry? entry(String id) => _entries[id];

  List<VaultEntry> ofKind(ItemKind kind) => [
    for (final e in _entries.values)
      if (e.kind == kind && !isTrashed(e.id)) e,
  ];

  /// Trashed: deleted, or a folder of its chain deleted (seen-set: a stored loop never hangs).
  bool isTrashed(String id) =>
      _chainOf(id).any((up) => _entries[up]?.item.deleted ?? false);

  // [start], then each folder above it; the seen-set stops at a stored loop.
  Iterable<String> _chainOf(String? start) sync* {
    final seen = <String>{};
    for (
      String? up = start;
      up != null && seen.add(up);
      up = _entries[up]?.folderId
    ) {
      yield up;
    }
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
    if (_chainOf(parentId).contains(id)) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'is the folder itself or inside it',
      );
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

  /// A personal copy of [mine] under a new id at revision 0, name suffixed, secret re-sealed; an org item's
  /// copy leaves its org folder. Null for an unknown type.
  Future<Item?> conflictCopy(Item mine, {required String suffix}) =>
      sealer.conflictCopyIn(
        _personal,
        mine,
        suffix: suffix,
        folderId: mine.scope == ItemScope.personal ? mine.folderId : null,
      );

  /// An `ok` host with its inherited values; null for anything else.
  ({HostMeta meta, ResolvedHost resolved, bool isOrg})? hostLookup(String id) {
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
      isOrg: e.item.scope == ItemScope.org,
    );
  }

  FolderMeta? _folderOf(String id) {
    final f = _entries[id];
    return f != null && f.state == EntryState.ok && f.kind == ItemKind.folder
        ? FolderMeta.fromJson(f.meta)
        : null;
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
    await _write(
      withDeleted(mirror, current.item, deleted: deleted),
      current.meta!,
    );
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
    // Locked: a late sync round finds nothing to rebuild.
    if (key == null) return;
    final writes = _writes;
    final queued = {for (final e in mirror.outbox()) e.item.id: e.item};
    // The outbox overlays the server row.
    final rows = {for (final i in mirror.items()) i.id: i, ...queued};
    final next = <String, VaultEntry>{};
    final replayed = <String>{};
    for (final item in rows.values) {
      // Locked while this round ran.
      if (_key == null) return;
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
      final built = await _built(
        item,
        () => open(item, PayloadPart.meta, fromServer: fromServer),
        pending: !fromServer,
      );
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
    hostKeys._rebuild(next.values);
    if (isTracing(TraceArea.vault)) {
      final odd = next.values.where((e) => e.state != EntryState.ok).length;
      trace(
        TraceArea.vault,
        'reload: ${next.length} entries, $odd not ok, outbox ${queued.length}',
      );
    }
    await hostKeys._seed(_entries.values);
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
    final item = await sealer.sealItem(
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

  /// Hands [items] to the outbox at once, without touching the entries (rotation reloads once, after).
  Future<void> sendAll(List<Item> items) => _send(items);

  // Sends item and shows it from meta, its plaintext in hand; the sync round reloads what else changed.
  Future<void> _write(Item item, Map<String, Object?> meta) async {
    trace(
      TraceArea.vault,
      'write ${item.type} ${shortId(item.id)}${item.deleted ? ' (trash)' : ''}',
    );
    await _send([item]);
    // Locked while sending.
    if (_key == null) return;
    if (item.scope == ItemScope.org && keyring == null) return;
    _entries[item.id] = _written(item, meta);
    _writes++;
    hostKeys._rebuild(_entries.values);
    await ledger.saveIfChanged();
    notifyListeners();
  }

  Uint8List _requireKey() => _key ?? (throw StateError('locked'));
}
