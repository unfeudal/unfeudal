// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/maintenance.dart';

import '../support/test_server.dart';

void main() {
  late TestServer s;
  setUp(() async => s = await TestServer.start());
  tearDown(() => s.close());
  Future<List<String>> owners() async => [
    for (final r in await s.db.query(
      'SELECT email FROM users WHERE is_instance_owner = 1',
    ))
      r['email']! as String,
  ];

  test(
    'moves the Instance Owner; the old one loses the admin routes at once',
    () async {
      final old = await s.setupOwner();
      final bob = await s.createUser('bob@example.org');
      await transferOwner(s.db, 'bob@example.org');
      expect(await owners(), ['bob@example.org']);
      expect(
        (await s.get('/api/v1/admin/users', token: old.accessToken)).status,
        403,
      );
      expect(
        (await s.get('/api/v1/admin/users', token: bob.accessToken)).status,
        200,
      );
    },
  );

  test(
    'unknown or disabled target, and the current owner, change nothing',
    () async {
      await s.setupOwner();
      final bob = await s.createUser('bob@example.org');
      await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
        'u': bob.userId,
      });
      await expectLater(
        transferOwner(s.db, 'ghost@example.org'),
        throwsStateError,
      );
      await expectLater(
        transferOwner(s.db, 'bob@example.org'),
        throwsStateError,
      );
      await transferOwner(s.db, 'owner@example.org');
      expect(await owners(), ['owner@example.org']);
    },
  );
}
