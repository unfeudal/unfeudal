// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

/// True for localhost, *.local, 127/8, 10/8, 172.16/12, 192.168/16, 169.254/16, ::1, fc00::/7, fe80::/10,
/// and IPv4-mapped forms of those IPv4 ranges. Case-insensitive; ignores a trailing dot and an IPv6 zone.
bool isLanHost(Uri uri) {
  var host = uri.host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.isEmpty) return false;
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final zone = host.indexOf('%');
  final ip = InternetAddress.tryParse(zone < 0 ? host : host.substring(0, zone))
      ?.rawAddress;
  if (ip == null) return false;
  if (ip.length == 4) return zone < 0 && _lanV4(ip);
  final zeros10 = ip.take(10).every((b) => b == 0);
  // ::ffff:a.b.c.d
  if (zeros10 && ip[10] == 0xff && ip[11] == 0xff) {
    return _lanV4(ip.sublist(12));
  }
  // ::1
  if (zeros10 && ip.skip(10).take(5).every((b) => b == 0) && ip[15] == 1) {
    return true;
  }
  return (ip[0] & 0xfe) == 0xfc || (ip[0] == 0xfe && (ip[1] & 0xc0) == 0x80);
}

bool _lanV4(List<int> a) =>
    a[0] == 127 ||
    a[0] == 10 ||
    (a[0] == 172 && a[1] >= 16 && a[1] <= 31) ||
    (a[0] == 192 && a[1] == 168) ||
    (a[0] == 169 && a[1] == 254);
