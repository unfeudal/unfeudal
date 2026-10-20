// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../debug_trace.dart';
import '../storage/local_mirror.dart';

/// What the mirror and the outbox become once the server answered a write: accepted or 409.
class ConflictResolver {
  ConflictResolver({
    required this.mirror,
    required this.deviceId,
    required this.markChanged,
    required this.copyOf,
  });

  final LocalMirror mirror;
  final String deviceId;
  final void Function() markChanged;
  final Future<Item?> Function(Item mine, {required bool personal}) copyOf;

  // The server accepted sent: mirror it; drop the outbox entry unless it was edited meanwhile (then rebase it).
  void settle(Item sent, Item stored) {
    mirror.upsertItems([stored]);
    markChanged();
    final queued = mirror.outboxEntry(sent.id);
    if (queued == null) return;
    if (jsonEncode(queued.item.toJson()) == jsonEncode(sent.toJson())) {
      mirror.removeOutbox(sent.id);
    } else {
      mirror.rebaseOutbox(sent.id, stored.revision!);
    }
  }

  Future<void> resolve(Item mine, Item? current) async {
    markChanged();
    // Gone without a tombstone: create it again.
    if (current == null) {
      return mirror.rebaseOutbox(mine.id, 0);
    }
    final ours =
        current.updatedDevice == deviceId &&
        current.deleted == mine.deleted &&
        jsonEncode(current.meta?.toJson()) == jsonEncode(mine.meta?.toJson());
    // A meta-only write sends no secret, so only a secret we sent can differ from the server's.
    final sameSecret =
        mine.secret == null ||
        jsonEncode(current.secret?.toJson()) ==
            jsonEncode(mine.secret!.toJson());
    // Our own write, whose response was lost.
    if (ours && sameSecret) return settle(mine, current);
    // The server holds our earlier write; the secret changed since, so send it on top.
    if (ours) return mirror.rebaseOutbox(mine.id, current.revision!);
    trace(TraceArea.sync, 'conflict on ${mine.kind.name} ${shortId(mine.id)}');
    mirror.upsertItems([current]);
    // The server copy of a known host is kept; the ledger's hostPins decide here.
    if (mine.kind == ItemKind.knownHost) {
      return mirror.removeOutbox(mine.id);
    }
    final deletedThere = current.purged || (current.deleted && !mine.deleted);
    // Our delete (restorable) or the profile (last write wins) goes over the server's.
    if (!deletedThere && (mine.deleted || mine.kind == ItemKind.profile)) {
      return mirror.rebaseOutbox(mine.id, current.revision!);
    }
    // Otherwise the server's deletion or version wins; an edit of ours is kept as a copy.
    final copy = mine.deleted ? null : await copyOf(mine, personal: false);
    mirror.removeOutbox(mine.id);
    if (copy != null) mirror.enqueue(copy, baseRevision: 0);
  }
}
