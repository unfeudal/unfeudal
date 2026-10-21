// SPDX-License-Identifier: Apache-2.0
import '../payload/inheritance.dart';

/// The most jump hosts a chain may cross; POST /events/ssh enforces the same limit.
const maxJumpHosts = 8;

class JumpLoop implements Exception {
  JumpLoop(this.path);
  final List<String> path;
  @override
  String toString() => 'JumpLoop(${path.join(' -> ')})';
}

class JumpTooDeep implements Exception {
  JumpTooDeep(this.path);
  final List<String> path;
  @override
  String toString() => 'JumpTooDeep(${path.length - 1} jump hosts)';
}

class JumpHostMissing implements Exception {
  JumpHostMissing(this.hostId);
  final String hostId;
  @override
  String toString() => 'JumpHostMissing($hostId)';
}

/// Jump hosts to cross before [hostId], outermost first. [lookup] returns the resolved host
/// (own value or folder default), or null for a missing, trashed, unreadable or non-host item.
List<String> resolveJumpChain(
  String hostId,
  ResolvedHost? Function(String id) lookup,
) {
  final hops = <String>[];
  final seen = {hostId};
  var next = lookup(hostId)?.jumpHostId;
  while (next != null) {
    if (!seen.add(next)) throw JumpLoop([hostId, ...hops, next]);
    final hop = lookup(next) ?? (throw JumpHostMissing(next));
    hops.add(next);
    if (hops.length > maxJumpHosts) throw JumpTooDeep([hostId, ...hops]);
    next = hop.jumpHostId;
  }
  return hops.reversed.toList();
}
