// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';

import '../../support/test_server.dart';

void main() {
  test('sets the mail language; only en and fr; needs a token', () async {
    final s = await TestServer.start();
    addTearDown(s.close);
    final o = await s.setupOwner();
    expect(
      (await s.put(
        '/api/v1/account/locale',
        token: o.accessToken,
        body: {'locale': 'fr'},
      )).status,
      204,
    );
    expect(
      (await s.db.query('SELECT locale FROM users')).single['locale'],
      'fr',
    );
    for (final bad in <Map<String, Object?>>[
      {'locale': 'de'},
      {'locale': 'FR'},
      {'locale': 1},
      {},
    ]) {
      expect(
        (await s.put(
          '/api/v1/account/locale',
          token: o.accessToken,
          body: bad,
        )).status,
        400,
        reason: '$bad',
      );
    }
    expect(
      (await s.put('/api/v1/account/locale', body: {'locale': 'en'})).status,
      401,
    );
    expect(
      (await s.db.query('SELECT locale FROM users')).single['locale'],
      'fr',
    );
  });
}
