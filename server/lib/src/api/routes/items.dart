// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../items/item_write.dart';
import '../app.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// Creates or updates one item under optimistic concurrency (`If-Match: <revision>`, 0 = create).
Future<Response> putItem(Request request) async {
  final deps = depsOf(request);
  final id = parseUuid(request.params['id']!);
  final ifMatch = parseIfMatch(request.headers['if-match']);
  final input = parseItemInput(id, await readJson(request));
  final stored = await deps.db.transaction(
    (tx) => writeItem(
      deps,
      tx,
      authOf(request),
      input,
      ifMatch,
      ip: clientIpOf(request).address,
    ),
  );
  return jsonResponse(stored.toJson());
}
