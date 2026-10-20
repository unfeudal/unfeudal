// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'api/api_client.dart';

enum AppStage { booting, login, setup, join, unlock, home, mirrorTooNew }

/// Why the login screen shows after a session ended without the user signing out.
enum SignOutReason { deviceRevoked, sessionExpired }

/// A server reached over anything but https, or plain http outside the LAN or without `plain_http_lan`.
class InsecureServer implements Exception {
  const InsecureServer();
}

/// Plain http on the LAN that the user did not confirm.
class PlainHttpRefused implements Exception {
  const PlainHttpRefused();
}

/// The platform name and its wire value; never the hostname.
DeviceInput deviceInput() {
  if (Platform.isWindows) return (name: 'Windows', platform: 'windows');
  if (Platform.isMacOS) return (name: 'macOS', platform: 'macos');
  if (Platform.isLinux) return (name: 'Linux', platform: 'linux');
  return (name: 'Other', platform: 'other');
}
