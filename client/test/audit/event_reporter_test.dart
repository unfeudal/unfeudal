// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/audit/event_reporter.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/sync_harness.dart';

void main() {
  test('reports sessions, forwards and reveals in order, ids only; nothing when off; failures dropped', () async {
    final h = SyncHarness(capabilities: ['client_events', 'sync']);
    final login = await h.signIn();
    final api = ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken;
    final events = StreamController<AppEvent>.broadcast();
    var enabled = true;
    EventReporter(
      events: events.stream,
      api: () => api,
      enabled: () => enabled,
    ).start();
    final (host, bastion) = (newId(), newId());
    final f = PortForward(localPort: 5432, remoteHost: 'db', remotePort: 5432);
    for (final e in <AppEvent>[
      JumpUsed(hostId: host, hopIds: [bastion]),
      ConnectSucceeded(hostId: host, user: 'root', tags: const []),
      ForwardStarted(hostId: host, forward: f),
      ForwardStopped(hostId: host, localPort: 5432),
      SessionClosed(hostId: host),
      ConnectSucceeded(hostId: host, user: 'root', tags: const []),
      SecretRevealed(itemId: host),
    ]) {
      events.add(e);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
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
    h.eventStatus = 429;
    events.add(SecretRevealed(itemId: host));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      h.reported,
      hasLength(6),
      reason: 'a refused report is dropped, never thrown',
    );
    h.eventStatus = null;
    enabled = false;
    events.add(SecretRevealed(itemId: host));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.reported, hasLength(6), reason: 'client_events off');
  });

  test('AppState emits SessionClosed once per connected tab: closed, ended by the host, or locked', () async {
    final h = SyncHarness(capabilities: ['client_events', 'sync']);
    await h.createAccount('camille@example.org', 'password-123');
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final AppState s = testAppState(harness: h, ssh: ssh)
      ..dialogs = (FakeDialogs()..accept = true);
    await s.boot();
    await s.login(
      server: h.baseUrl,
      email: 'camille@example.org',
      password: 'password-123',
    );
    final closed = <String>[];
    s.events.listen((e) {
      if (e is SessionClosed) closed.add(e.hostId);
    });
    final [a, b, c] = [
      for (final n in ['a', 'b', 'c'])
        await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson(n, user: 'root'),
        ),
    ];
    await s.closeTab(await s.connect(a));
    await s.connect(b);
    ssh.shells.last.hangUp();
    await Future<void>.delayed(Duration.zero);
    await s.connect(c);
    await Future.sync(s.lock);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, [a, b, c]);
    expect(h.reported.where((r) => r.body['event'] == 'close'), hasLength(3));
  });
}
