// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const idA = '4a6c8e0a-2b4d-4f6a-8c0e-2a4c6e8a0c2e';
const jump = '1b3d5f7a-9c1e-4a3b-9d5f-7a9c1e3b5d7f';

Map<String, Object?> host([Map<String, Object?> over = const {}]) => {
  'schemaVersion': 1,
  'name': 'web',
  'address': '10.0.0.5',
  'user': null,
  'identityId': null,
  'tags': <String>[],
  'notes': null,
  'startupCommand': null,
  ...over,
};
Map<String, Object?> fwd([Map<String, Object?> over = const {}]) => {
  'localPort': 8443,
  'remoteHost': '127.0.0.1',
  'remotePort': 443,
  'autoStart': false,
  ...over,
};

void main() {
  test('full host round-trips in field order, unknown fields first', () {
    // Written in wire field order: host() would append the optional keys last.
    final json = {
      'colorLabel': 'red',
      'schemaVersion': 1,
      'name': 'web',
      'address': '10.0.0.5',
      'port': 2222,
      'user': 'deploy',
      'identityId': idA,
      'identityMode': 'perMember',
      'tags': ['prod'],
      'notes': 'n',
      'startupCommand': 'tmux',
      'forwards': [
        {'note': 'future', ...fwd()},
        fwd({'localPort': 80, 'allowLowPorts': true}),
      ],
      'jumpHostId': jump,
    };
    final h = HostMeta.fromJson(json);
    expect(
      (h.port, h.identityMode, h.forwards.length),
      (2222, IdentityMode.perMember, 2),
    );
    expect(h.forwards.first.extra, {'note': 'future'});
    expect(jsonEncode(h.toJson()), jsonEncode(json));
  });

  test('defaults and write-when rules', () {
    final h = HostMeta.fromJson(host());
    expect(
      (h.port, h.identityMode, h.jumpHostId),
      (null, IdentityMode.shared, null),
    );
    expect(h.tags, isEmpty);
    expect(h.forwards, isEmpty);
    expect(
      h.toJson().keys,
      isNot(
        anyElement(isIn(['port', 'identityMode', 'forwards', 'jumpHostId'])),
      ),
    );
    expect(jsonEncode(h.toJson()), jsonEncode(host()));
  });

  test('required strings are trimmed; schemaVersion is kept', () {
    final h = HostMeta.fromJson(host({'name': '  web  ', 'schemaVersion': 2}));
    expect(
      (h.name, h.schemaVersion, h.isNewer, Payload.knownSchemaVersion),
      ('web', 2, true, 1),
    );
    expect(
      (
        PayloadLimits.name,
        PayloadLimits.address,
        PayloadLimits.notes,
        PayloadLimits.forwards,
      ),
      (100, 253, 10000, 32),
    );
    expect(
      HostMeta.fromJson(host({'name': '\u{1F600}' * 100})).name.runes.length,
      100,
    );
  });

  test('malformed hosts throw FormatException', () {
    final bad = [
      host({'name': '   '}),
      host({'name': 'x' * 101}),
      host({'address': ''}),
      host({'address': 'a' * 254}),
      host({'port': 0}),
      host({'port': 65536}),
      host({'port': '22'}),
      host({'user': 'u' * 65}),
      host({'identityId': 'id-1'}),
      host({'identityMode': 'team'}),
      host({'tags': List.filled(33, 't')}),
      host({
        'tags': ['t' * 65],
      }),
      host({'notes': 'n' * 10001}),
      host({'startupCommand': 'c' * 4097}),
      host({
        'forwards': List.generate(33, (i) => fwd({'localPort': 2000 + i})),
      }),
      host({'jumpHostId': 'h1'}),
      host({
        'forwards': [
          fwd({'remoteHost': 'a b'}),
        ],
      }),
      host({
        'forwards': [
          fwd({'remoteHost': ' '}),
        ],
      }),
      host({
        'forwards': [
          fwd({'remotePort': 0}),
        ],
      }),
      host({
        'forwards': [
          fwd({'allowLowPorts': false}),
        ],
      }),
      host({
        'forwards': [
          fwd({'localPort': 22}),
        ],
      }),
      host({
        'forwards': [
          fwd(),
          fwd({'remotePort': 80}),
        ],
      }),
      host()..remove('schemaVersion'),
    ];
    for (final json in bad) {
      expect(
        () => HostMeta.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });

  test('validateForwards reports low ports and duplicates by index', () {
    final list = [
      PortForward.fromJson(fwd({'localPort': 2222})),
      PortForward(localPort: 80, remoteHost: 'h', remotePort: 80),
      PortForward(localPort: 2222, remoteHost: 'h', remotePort: 22),
    ];
    expect(
      [for (final i in validateForwards(list)) (i.index, i.kind)],
      [
        (1, ForwardIssueKind.lowPortNotAllowed),
        (2, ForwardIssueKind.duplicateLocalPort),
      ],
    );
    expect(
      validateForwards([
        PortForward(
          localPort: 80,
          remoteHost: 'h',
          remotePort: 80,
          allowLowPorts: true,
        ),
      ]),
      isEmpty,
    );
  });
}
