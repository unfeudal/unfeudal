// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

class FakePeer implements HttpConnectionInfo {
  FakePeer(String ip) : remoteAddress = InternetAddress(ip);
  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 40000;
  @override
  int get localPort => 8080;
}
