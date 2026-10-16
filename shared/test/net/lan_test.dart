// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

bool lan(String url) => isLanHost(Uri.parse(url));

void main() {
  test('loopback, private, link-local and local names are LAN', () {
    for (final url in [
      'http://localhost:8080',
      'http://LOCALHOST',
      'http://nas.local',
      'http://nas.local.',
      'http://127.0.0.1',
      'http://10.1.2.3',
      'http://172.16.0.1',
      'http://172.31.255.255',
      'http://192.168.1.10:8080',
      'http://169.254.10.1',
      'http://[::1]:8080',
      'http://[fc00::1]',
      'http://[fd12:3456::1]',
      'http://[fe80::1]',
      'http://[fe80::1%25eth0]:8080',
      'http://[::ffff:192.168.1.2]',
    ]) {
      expect(lan(url), isTrue, reason: url);
    }
  });

  test('public addresses and look-alike names are not LAN', () {
    for (final url in [
      'http://vault.example.org',
      'http://8.8.8.8',
      'http://11.0.0.1',
      'http://172.15.255.255',
      'http://172.32.0.1',
      'http://192.169.0.1',
      'http://169.255.0.1',
      'http://[2001:db8::1]',
      'http://[fec0::1]',
      'http://[::ffff:8.8.8.8]',
      'http://localhost.example.org',
      'http://x.local.example.com',
      'http://',
    ]) {
      expect(lan(url), isFalse, reason: url);
    }
  });
}
