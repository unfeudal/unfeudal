// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/audit/event_reporter.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  late StreamController<AppEvent> events;
  late bool enabled;
  final host = newId();

  Future<void> until(bool Function() isDone) async {
    while (!isDone()) {
      await pumpEventQueue();
    }
  }

  setUp(() async {
    h = SyncHarness(capabilities: ['client_events', 'sync']);
    final login = await h.signIn();
    final api = ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken;
    events = StreamController<AppEvent>.broadcast();
    addTearDown(events.close);
    enabled = true;
    EventReporter(
      events: events.stream,
      api: () => api,
      enabled: () => enabled,
    ).start();
  });

  test('reports sessions, forwards and reveals in order, ids only', () async {
    final bastion = newId();
    final f = PortForward(localPort: 5432, remoteHost: 'db', remotePort: 5432);
    for (final e in <AppEvent>[
      JumpUsed(hostId: host, hopIds: [bastion]),
      ConnectSucceeded(hostId: host, user: 'root'),
      ForwardStarted(hostId: host, forward: f),
      ForwardStopped(hostId: host, localPort: 5432),
      SessionClosed(hostId: host),
      ConnectSucceeded(hostId: host, user: 'root'),
      SecretRevealed(itemId: host),
    ]) {
      events.add(e);
    }
    await until(() => h.reported.length == 6);
    expect(
      [
        for (final r in h.reported) [r.route, r.body],
      ],
      [
        [
          'POST /events/ssh',
          {
            'event': 'open',
            'hostItemId': host,
            'jumpHostItemIds': [bastion],
          },
        ],
        [
          'POST /events/ssh',
          {'event': 'forward_start', 'hostItemId': host, 'localPort': 5432},
        ],
        [
          'POST /events/ssh',
          {'event': 'forward_stop', 'hostItemId': host, 'localPort': 5432},
        ],
        [
          'POST /events/ssh',
          {'event': 'close', 'hostItemId': host},
        ],
        [
          'POST /events/ssh',
          {'event': 'open', 'hostItemId': host},
        ],
        [
          'POST /events/reveal',
          {'itemId': host},
        ],
      ],
    );
  });

  test('a refused report is dropped, never thrown', () async {
    h.eventStatus = 429;
    events.add(SecretRevealed(itemId: host));
    await until(() => h.requests.contains('POST /api/v1/events/reveal'));
    await pumpEventQueue();
    expect(h.reported, isEmpty);
  });

  test('nothing is reported while client_events is off', () async {
    enabled = false;
    events.add(SecretRevealed(itemId: host));
    await pumpEventQueue();
    expect(h.requests, isNot(contains('POST /api/v1/events/reveal')));
  });
}
