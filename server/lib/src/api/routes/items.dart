// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';

import '../../items/item_write.dart';
import '../../net/client_ip.dart';
import '../app.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// Creates or updates one item under optimistic concurrency (`If-Match: <revision>`, 0 = create).
Future<Response> putItem(Request request, String id) async {
  final deps = depsOf(request);
  parseUuid(id);
  final ifMatch = parseIfMatch(request.headers['if-match']);
  final input = parseItemInput(id, await readJson(request));
  final stored = await deps.db.transaction(
    (tx) => writeItem(
      deps,
      tx,
      authOf(request),
      input,
      ifMatch,
      ip: clientIp(request, deps.config.trustedProxies).address,
    ),
  );
  return jsonResponse(stored.toJson());
}
