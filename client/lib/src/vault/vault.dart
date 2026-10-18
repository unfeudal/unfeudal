// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

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

  /// Returns the ledger result: false when the sealed ledger could not be opened (the caller reports it).
  Future<bool> unlock(Uint8List userKey) async {
    final key = _key = Uint8List.fromList(userKey);
    final ledgerOpened = await ledger.load(key);
    await reload();
    return ledgerOpened;
  }

  void lock() {
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
      if (e.kind == kind && !e.item.deleted) e,
  ];

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
        continue; // org items: p6
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
    if (current != null && current.folderId != folderId && secret == null) {
      secret = await _secretJson(itemId); // a move re-seals both parts: the server refuses a moved item without its secret
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
    if (opened == null) throw StateError('replayed secret');
    return opened.json;
  }

  Future<void> _write(Item item) async {
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
