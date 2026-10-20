// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../storage/local_mirror.dart';
import 'sync_engine.dart';

/// What the server said about itself: the last ApiInfo seen (a sync round or a server check), else the one
/// the last sync round stored.
class ServerInfo {
  ServerInfo(this._mirror);

  // The mirror is replaced at each sign-in.
  final LocalMirror? Function() _mirror;

  ApiInfo? last;

  /// The server version of the last ApiInfo seen with a token, if any.
  String? get version => last?.server ?? _stored?.server;

  /// The effective trash retention in days (0 = never purged); null before the server said.
  int? get trashDays => _info?.trashDays;

  /// Where the server publishes its source (AGPL); null before the server said.
  String? get source => _info?.source;

  /// False when no ApiInfo was ever seen.
  bool has(Flag flag) => _info?.has(flag) ?? false;

  ApiInfo? get _info => last ?? _stored;

  ApiInfo? get _stored => switch (_mirror()) {
    final mirror? => storedApiInfo(mirror),
    null => null,
  };
}
