// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../version.dart';
import '../deps.dart';
import '../json.dart';

/// Public form for anyone; the full form with a valid access token (MAC and
/// expiry only: it reveals nothing secret). An invalid token is ignored.
Response info(Request request) {
  final deps = depsOf(request);
  final full =
      deps.access.verifyHeader(request.headers['authorization']) != null;
  final config = deps.config;
  return jsonResponse(
    ApiInfo(
      api: [1],
      minClient: config.minClientVersion,
      latestClient: latestClientVersion,
      capabilities: full
          ? deps.features.capabilities()
          : deps.features.publicCapabilities(),
      server: full ? serverVersion : null,
      instanceEpoch: full ? deps.instanceEpoch : null,
      source: full ? '${config.sourceUrl}' : null,
      trashDays: full ? config.trashRetentionDays : null,
    ).toJson(),
  );
}
