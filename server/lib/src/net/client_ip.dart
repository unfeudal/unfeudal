// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Key under which shelf_io stores the socket's HttpConnectionInfo.
const connectionInfoKey = 'shelf.io.connection_info';

InternetAddress _unmap(InternetAddress address) {
  final raw = address.rawAddress;
  final mapped =
      raw.length == 16 &&
      raw.take(10).every((byte) => byte == 0) &&
      raw[10] == 0xff &&
      raw[11] == 0xff;
  return mapped
      ? InternetAddress.fromRawAddress(Uint8List.fromList(raw.sublist(12)))
      : address;
}

class Cidr {
  Cidr._(this._net, this._prefix);

  final Uint8List _net;
  final int _prefix;

  static Cidr parse(String text) {
    final slash = text.indexOf('/');
    final addr = slash < 0
        ? null
        : InternetAddress.tryParse(text.substring(0, slash));
    final prefix = slash < 0 ? null : int.tryParse(text.substring(slash + 1));
    if (addr == null ||
        prefix == null ||
        prefix < 0 ||
        prefix > addr.rawAddress.length * 8) {
      throw FormatException('invalid CIDR', text);
    }
    return Cidr._(addr.rawAddress, prefix);
  }

  bool contains(InternetAddress address) {
    final raw = _unmap(address).rawAddress;
    if (raw.length != _net.length) return false;
    for (var bit = 0; bit < _prefix; bit++) {
      final mask = 0x80 >> (bit % 8);
      if ((raw[bit ~/ 8] & mask) != (_net[bit ~/ 8] & mask)) return false;
    }
    return true;
  }
}

/// Socket peer; X-Forwarded-For only when the peer is a trusted proxy, then the right-most untrusted hop.
InternetAddress clientIp(Request request, List<Cidr> trusted) {
  final info = request.context[connectionInfoKey];
  if (info is! HttpConnectionInfo) throw StateError('no connection info');
  bool isTrusted(InternetAddress address) =>
      trusted.any((cidr) => cidr.contains(address));
  var ip = _unmap(info.remoteAddress);
  if (!isTrusted(ip)) return ip;
  final hops = (request.headers['x-forwarded-for'] ?? '')
      .split(',')
      .map((hop) => hop.trim())
      .where((hop) => hop.isNotEmpty);
  for (final hop in hops.toList().reversed) {
    final hopAddress = InternetAddress.tryParse(hop);
    // A malformed hop: keep the nearest trusted one.
    if (hopAddress == null) return ip;
    ip = _unmap(hopAddress);
    if (!isTrusted(ip)) return ip;
  }
  // Every hop trusted: the left-most.
  return ip;
}

/// Rate-limit network: IPv4 address, or the first 4 groups of IPv6 as `a:b:c:d::/64`.
String netOf(InternetAddress address) {
  final unmapped = _unmap(address);
  if (unmapped.type == InternetAddressType.IPv4) return unmapped.address;
  final raw = unmapped.rawAddress;
  final groups = [
    for (var i = 0; i < 8; i += 2)
      ((raw[i] << 8) | raw[i + 1]).toRadixString(16),
  ];
  return '${groups.join(':')}::/64';
}
