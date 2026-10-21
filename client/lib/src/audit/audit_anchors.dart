// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../storage/local_mirror.dart';

enum AnchorAlertKind { rewritten, vanished }

typedef AnchorAlert = ({String scope, int seq, AnchorAlertKind kind});

/// kv.anchors: {scope: {"seq", "hash"}}, the newest event this device saw per chain. Read on every call (no cache),
/// so an accepted restore that empties kv.anchors needs no hook.
class AuditAnchors {
  AuditAnchors(this.mirror);
  final LocalMirror mirror;

  Map<String, ({int seq, String hash})> _load() {
    final raw = mirror.kv(KvKey.anchors);
    if (raw == null) return {};
    try {
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, Object?>).entries)
          key: (
            seq: (value! as Map)['seq']! as int,
            hash: (value as Map)['hash']! as String,
          ),
      };
    } on Object {
      // jsonDecode and the casts throw on a malformed value: start over, it holds no secret.
      return {};
    }
  }

  ({int seq, String hash})? anchorOf(String scope) => _load()[scope];

  /// [events] from any view. [completeScope]: [events] hold that whole chain from its first remaining event.
  List<AnchorAlert> checkAndAdvance(
    List<AuditEvent> events, {
    String? completeScope,
  }) {
    final anchors = _load();
    final alerts = <AnchorAlert>[];
    final byScope = <String, List<AuditEvent>>{?completeScope: []};
    for (final e in events) {
      (byScope[e.scope] ??= []).add(e);
    }
    for (final MapEntry(key: scope, value: list) in byScope.entries) {
      final anchor = anchors[scope];
      var alert = false;
      if (anchor != null) {
        final same = list.where((e) => e.seq == anchor.seq).firstOrNull;
        final checkpoints = [
          for (final e in list)
            if (e.action == 'audit.checkpoint' &&
                e.targetIds.length == 2 &&
                e.targetIds[0].startsWith('seq:'))
              (
                seq: int.tryParse(e.targetIds[0].substring(4)) ?? -1,
                hash: e.targetIds[1].replaceFirst('hash:', ''),
              ),
        ];
        if ((same != null && same.hash != anchor.hash) ||
            checkpoints.any(
              (c) => c.seq == anchor.seq && c.hash != anchor.hash,
            )) {
          alerts.add((
            scope: scope,
            seq: anchor.seq,
            kind: AnchorAlertKind.rewritten,
          ));
          alert = true;
        } else if (same == null &&
            scope == completeScope &&
            !checkpoints.any((c) => c.seq >= anchor.seq)) {
          alerts.add((
            scope: scope,
            seq: anchor.seq,
            kind: AnchorAlertKind.vanished,
          ));
          alert = true;
        }
      }
      if (!alert && list.isNotEmpty) {
        final newest = list.reduce((x, y) => x.seq >= y.seq ? x : y);
        if (anchor == null || newest.seq > anchor.seq) {
          anchors[scope] = (seq: newest.seq, hash: newest.hash);
        }
      }
    }
    mirror.setKv(
      KvKey.anchors,
      jsonEncode({
        for (final MapEntry(:key, :value) in anchors.entries)
          key: {'seq': value.seq, 'hash': value.hash},
      }),
    );
    return alerts;
  }
}
