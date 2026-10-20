// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';

import '../audit/audit_log.dart';
import '../db/db.dart';
import 'deps.dart';
import 'middleware.dart';

typedef AuditWrite = Future<void> Function(
  AuditScope scope,
  String action,
  List<String> targetIds,
);

/// An append bound to [tx], the actor (by default the token's user and device) and the client address.
AuditWrite auditWriter(
  Request request,
  Tx tx, {
  ({String? user, String? device})? actor,
}) {
  final deps = depsOf(request);
  final who =
      actor ?? (user: authOf(request).userId, device: authOf(request).deviceId);
  final ip = clientIpOf(request).address;
  return (scope, action, targetIds) => deps.audit.append(
    tx,
    scope: scope,
    action: action,
    actorUser: who.user,
    actorDevice: who.device,
    ip: ip,
    targetIds: targetIds,
  );
}
