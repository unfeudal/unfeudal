// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const _addressInUse = {48, 98, 10048}; // EADDRINUSE: macOS, Linux, Windows

// The OS says the port is taken, or the Dart VM does: it refuses a second bind of a port this process
// already holds (another tab's forward) before asking the OS.
bool _isInUse(SocketException e) =>
    _addressInUse.contains(e.osError?.errorCode) ||
    (e.osError?.message.contains('shared flag') ?? false);

class PortInUse implements Exception {
  const PortInUse(this.port);
  final int port;

  @override
  String toString() => 'PortInUse($port)';
}

class ForwardBindFailed implements Exception {
  const ForwardBindFailed(this.port, this.cause);
  final int port;
  final OSError? cause;

  @override
  String toString() => 'ForwardBindFailed($port)';
}

/// One listening forward and the local connections it pipes.
class ForwardHandle {
  ForwardHandle._(this.forward, this._server);

  final PortForward forward;
  final ServerSocket _server;
  final _sockets = <Socket>{};

  InternetAddress get address => _server.address;

  void _track(Socket local) {
    _sockets.add(local);
    local.done.whenComplete(() => _sockets.remove(local)).ignore();
  }

  Future<void> close() async {
    await _server.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
  }
}

/// Local port forwards over one SSH connection; listeners bind the loopback address only.
class PortForwarder extends ChangeNotifier {
  PortForwarder(this._open);

  final Future<SSHSocket> Function(String host, int port) _open;
  final _active = <int, ForwardHandle>{};
  final _failed = <int, Object>{};

  Map<int, ForwardHandle> get active => Map.unmodifiable(_active);
  Map<int, Object> get failed => Map.unmodifiable(_failed);

  Future<ForwardHandle> start(PortForward f) async {
    final running = _active[f.localPort];
    if (running != null) return running;
    if (f.localPort < 1024 && !f.allowLowPorts) {
      throw ArgumentError.value(
        f.localPort,
        'localPort',
        'needs allowLowPorts',
      );
    }
    final ServerSocket server;
    try {
      // Loopback only, never 0.0.0.0 or ::, so the forward is not exposed to the network.
      server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        f.localPort,
      );
    } on SocketException catch (e) {
      final Exception error = _isInUse(e)
          ? PortInUse(f.localPort)
          : ForwardBindFailed(f.localPort, e.osError);
      _failed[f.localPort] = error;
      notifyListeners();
      throw error;
    }
    final handle = ForwardHandle._(f, server);
    server.listen((local) async {
      handle._track(local);
      try {
        final remote = await _open(f.remoteHost, f.remotePort);
        unawaited(
          remote.stream.cast<List<int>>().pipe(local).catchError((Object _) {}),
        );
        unawaited(
          local.cast<List<int>>().pipe(remote.sink).catchError((Object _) {}),
        );
      } on Object catch (_) {
        // Any failure to open the channel ends only this connection, never the forward.
        local.destroy();
      }
    });
    _active[f.localPort] = handle;
    _failed.remove(f.localPort);
    notifyListeners();
    return handle;
  }

  Future<void> stop(int localPort) async {
    final handle = _active.remove(localPort);
    if (handle == null) return;
    await handle.close();
    notifyListeners();
  }

  Future<void> stopAll() async {
    final handles = _active.values.toList();
    _active.clear();
    for (final h in handles) {
      await h.close();
    }
    notifyListeners();
  }
}
