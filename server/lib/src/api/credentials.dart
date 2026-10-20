// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';

import '../auth/rate_limit.dart';
import '../auth/secret_hash.dart';
import '../net/client_ip.dart';
import 'app.dart';

/// Rate-limit step of a credential check: count ip, acct|ip and acct before
/// any credential is checked; an attempt inside the account delay is 429.
Future<void> limitCredentials(Request request, String email) async {
  // ponytail: checked, not reserved; a queue that fills between here and the hash still counts that attempt
  refuseIfArgon2Busy();
  final deps = depsOf(request);
  final net = netOf(clientIpOf(request));
  await deps.limiter.hit([ipKey(net), acctIpKey(email, net), acctKey(email)]);
}

/// After the right credential: reset the acct keys. ip: stays counted.
Future<void> clearCredentials(Request request, String email) async {
  final deps = depsOf(request);
  final net = netOf(clientIpOf(request));
  await deps.limiter.reset([acctIpKey(email, net), acctKey(email)]);
}
