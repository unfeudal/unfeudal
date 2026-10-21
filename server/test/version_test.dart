// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/version.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test(
    'server constants are X.Y.Z and the default min_client_version fits',
    () {
      expect(canonicalVersion(serverVersion), serverVersion);
      expect(
        compareVersions('0.1.0', latestClientVersion),
        lessThanOrEqualTo(0),
      );
    },
  );
}
