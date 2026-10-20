// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'audit_event.dart';

final genesisHash = '0' * 64;

// Keys sorted at every level, no spaces (jsonEncode's escaping); lists keep their order.
String _canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? v) => switch (v) {
  Map() => {
    for (final k in v.keys.map((k) => k as String).toList()..sort())
      k: _sorted(v[k]),
  },
  List() => [for (final x in v) _sorted(x)],
  _ => v,
};

String auditHash(String prevHash, Map<String, Object?> fields) =>
    sha256.convert(utf8.encode(prevHash + _canonicalJson(fields))).toString();

/// One whole chain (one scope). Starts at genesis (seq 1) or right after a checkpoint `[seq:N, hash:H]` of the
/// same list with N = first seq minus 1 and H = its prevHash; then contiguous seqs, linked hashes, recomputed hashes.
/// Returns the first seq that does not verify, null when the chain holds.
int? verifyChain(List<AuditEvent> events) {
  if (events.isEmpty) return null;
  final sorted = [...events]..sort((a, b) => a.seq.compareTo(b.seq));
  final first = sorted.first;
  final anchored = first.seq == 1
      ? first.prevHash == genesisHash
      : sorted.any(
          (e) =>
              e.scope == first.scope &&
              e.action == 'audit.checkpoint' &&
              e.targetIds.length == 2 &&
              e.targetIds[0] == 'seq:${first.seq - 1}' &&
              e.targetIds[1] == 'hash:${first.prevHash}',
        );
  if (!anchored) return first.seq;
  AuditEvent? prev;
  for (final e in sorted) {
    final linked =
        prev == null || (e.seq == prev.seq + 1 && e.prevHash == prev.hash);
    if (e.scope != first.scope ||
        !linked ||
        e.hash != auditHash(e.prevHash, e.hashFields())) {
      return e.seq;
    }
    prev = e;
  }
  return null;
}
