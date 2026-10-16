// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/net/client_ip.dart';

import '../support/peer.dart';

Request req(String peer, [String? xff]) => Request(
  'GET',
  Uri.parse('http://x/'),
  headers: {'x-forwarded-for': ?xff},
  context: {connectionInfoKey: FakePeer(peer)},
);

void main() {
  final proxies = [Cidr.parse('10.0.0.0/8'), Cidr.parse('fd00::/8')];

  test('Cidr matches v4 and v6 prefixes; malformed CIDRs throw', () {
    expect(
      Cidr.parse('10.0.0.0/8').contains(InternetAddress('10.200.1.1')),
      isTrue,
    );
    expect(
      Cidr.parse('10.0.0.0/8').contains(InternetAddress('11.0.0.1')),
      isFalse,
    );
    expect(
      Cidr.parse('192.168.1.0/25').contains(InternetAddress('192.168.1.128')),
      isFalse,
    );
    expect(Cidr.parse('fd00::/8').contains(InternetAddress('fd12::1')), isTrue);
    expect(
      Cidr.parse('10.0.0.0/8').contains(InternetAddress('::ffff:10.1.1.1')),
      isTrue,
    );
    expect(Cidr.parse('0.0.0.0/0').contains(InternetAddress('::1')), isFalse);
    for (final s in ['10.0.0.1', '10.0.0.0/33', 'x/8', '10.0.0.0/', '::/129']) {
      expect(() => Cidr.parse(s), throwsFormatException, reason: s);
    }
  });

  test('X-Forwarded-For from an untrusted peer is ignored', () {
    expect(
      clientIp(req('203.0.113.9', '1.2.3.4'), proxies).address,
      '203.0.113.9',
    );
    expect(
      clientIp(req('203.0.113.9', '1.2.3.4'), const []).address,
      '203.0.113.9',
    );
  });

  test('a trusted peer yields the right-most untrusted hop', () {
    expect(
      clientIp(
        req('10.0.0.2', '6.6.6.6, 198.51.100.4, 10.0.0.9'),
        proxies,
      ).address,
      '198.51.100.4',
    );
    expect(
      clientIp(req('10.0.0.2', '10.0.0.7, 10.0.0.9'), proxies).address,
      '10.0.0.7',
    );
    expect(
      clientIp(req('10.0.0.2', 'garbage, 10.0.0.9'), proxies).address,
      '10.0.0.9',
    );
    expect(clientIp(req('10.0.0.2'), proxies).address, '10.0.0.2');
    expect(
      clientIp(req('::ffff:10.0.0.2', '198.51.100.4'), proxies).address,
      '198.51.100.4',
    );
  });

  test('netOf: IPv4 as is, IPv6 as its /64, mapped IPv4 unwrapped', () {
    expect(netOf(InternetAddress('198.51.100.4')), '198.51.100.4');
    expect(netOf(InternetAddress('2001:db8:0:a:1:2:3:4')), '2001:db8:0:a::/64');
    expect(netOf(InternetAddress('::ffff:198.51.100.4')), '198.51.100.4');
  });
}
