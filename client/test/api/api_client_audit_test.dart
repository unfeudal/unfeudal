// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  late ApiClient api;
  late String me;
  setUp(() async {
    h = SyncHarness();
    final login = await h.signIn();
    me = login.account.userId;
    api = ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken;
  });

  test('audit pages a view with the opaque cursor', () async {
    for (var i = 0; i < 5; i++) {
      h.appendAudit('user:$me', 'device.added', actorUser: me);
    }
    h.appendAudit('instance', 'setup.completed');
    final first = await api.audit(scope: 'user', limit: 3);
    expect(
      [first.events.map((e) => e.seq).toList(), first.next != null],
      [
        [1, 2, 3],
        true,
      ],
    );
    final rest = await api.audit(scope: 'user', after: first.next, limit: 3);
    expect(
      [rest.events.map((e) => e.seq).toList(), rest.next],
      [
        [4, 5],
        null,
      ],
    );
    expect(
      (await api.audit()).events,
      hasLength(5),
      reason: 'me: own actions only',
    );
  });

  test('revisions, events and retention: the expected bodies; events pass in read-only', () async {
    final id = newId();
    h.serverPut(wireItem(id));
    h.serverPut(wireItem(id));
    expect((await api.revisions(id)).map((i) => i.revision).toList(), [2, 1]);
    await api.reportSsh(event: 'open', hostItemId: id, jumpHostItemIds: [id]);
    await api.reportSsh(
      event: 'forward_start',
      hostItemId: id,
      localPort: 5432,
    );
    api.isReadOnly = () => true;
    await api.reportReveal(id);
    expect(
      [
        for (final r in h.reported) [r.route, r.body],
      ],
      [
        [
          'POST /events/ssh',
          {
            'event': 'open',
            'hostItemId': id,
            'jumpHostItemIds': [id],
          },
        ],
        [
          'POST /events/ssh',
          {'event': 'forward_start', 'hostItemId': id, 'localPort': 5432},
        ],
        [
          'POST /events/reveal',
          {'itemId': id},
        ],
      ],
    );
    h.retention[testOrgId] = {
      'server': {'auditDays': 365, 'maxVersions': 0, 'trashDays': 30},
      'org': {'auditDays': 90, 'maxVersions': null, 'trashDays': null},
    };
    final r = await api.orgRetention(testOrgId);
    expect(r.server, {'auditDays': 365, 'maxVersions': 0, 'trashDays': 30});
    expect(r.org, {'auditDays': 90, 'maxVersions': null, 'trashDays': null});
  });
}
