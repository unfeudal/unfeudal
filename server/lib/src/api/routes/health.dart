// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';

import '../deps.dart';
import '../json.dart';

/// 200 when the database answers within 2 s, else 503.
Future<Response> healthz(Request request) async {
  try {
    await depsOf(request).db
        .query('SELECT 1 AS one')
        .timeout(const Duration(seconds: 2));
    return jsonResponse({'status': 'ok'});
  } on Object {
    // Any failure, timeout or driver error alike, means the database is down.
    return jsonResponse({'status': 'unavailable'}, status: 503);
  }
}
