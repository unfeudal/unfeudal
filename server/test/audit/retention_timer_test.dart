// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/audit/retention.dart';

import '../support/items.dart';
import '../support/test_server.dart';

void main() {
  test('startRetentionTimer runs the job at once, then keeps a 24 h timer until cancelled', () async {
    final s = await TestServer.start();
    addTearDown(s.close);
    final o = await s.setupOwner();
    final item = await testItem(o);
    await s.put(
      '/api/v1/items/${item['id']}',
      token: o.accessToken,
      body: item,
      headers: {'if-match': '0'},
    );
    await s.put(
      '/api/v1/items/${item['id']}',
      token: o.accessToken,
      body: {...item, 'deleted': true},
      headers: {'if-match': '1'},
    );
    s.clock.advance(const Duration(days: 31));
    final timer = startRetentionTimer(s.deps);
    addTearDown(timer.cancel);
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return !s.logLines.any((l) => l.contains('retention done'));
    }).timeout(const Duration(seconds: 5));
    expect(
      (await s.db.query('SELECT purged FROM items WHERE id = @i', {
        'i': item['id'],
      })).single['purged'],
      1,
    );
    expect(timer.isActive, isTrue);
  });
}
