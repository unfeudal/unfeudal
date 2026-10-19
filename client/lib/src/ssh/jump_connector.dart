// SPDX-License-Identifier: Apache-2.0
import 'package:dartssh2/dartssh2.dart';

import 'ssh_connector.dart';

abstract interface class HopClient {
  Future<SSHSocket> forwardLocal(String host, int port);
  Future<SshShell> shell();
  Future<void> close();
}

/// [over]: the previous hop's forwarded channel; null = direct TCP.
typedef HopOpener = Future<HopClient> Function(
  ConnectTarget target, {
  SSHSocket? over,
});

class JumpChainFailed implements Exception {
  JumpChainFailed(this.hostId, this.hostName, this.hopIndex, this.cause);
  final String hostId;
  final String hostName;
  final int hopIndex; // position in [...hops, target]
  final Object cause;
  @override
  String toString() => 'JumpChainFailed($hostId at $hopIndex: $cause)';
}

class JumpConnection {
  JumpConnection(this.target, this.hops);
  final HopClient target;
  final List<HopClient> hops;

  Future<void> close() async {
    await target.close();
    for (final h in hops.reversed) {
      await h.close();
    }
  }
}

/// [hops] outermost first. A failure closes what is open and never contacts the next hop.
Future<JumpConnection> connectChain(
  HopOpener open,
  List<ConnectTarget> hops,
  ConnectTarget target,
) async {
  final chain = [...hops, target];
  final opened = <HopClient>[];
  SSHSocket? over;
  for (var i = 0; i < chain.length; i++) {
    try {
      final client = await open(chain[i], over: over);
      opened.add(client);
      if (i < chain.length - 1) {
        over = await client.forwardLocal(
          chain[i + 1].address,
          chain[i + 1].port,
        );
      }
    } catch (e) {
      for (final c in opened.reversed) {
        await c.close().catchError((Object _) {});
      }
      throw JumpChainFailed(chain[i].hostId, chain[i].hostName, i, e);
    }
  }
  return JumpConnection(opened.last, opened.sublist(0, opened.length - 1));
}

HopOpener sshHopOpener(SshConnector connector, SshCallbacks callbacks) =>
    (target, {over}) => connector.connectHop(target, callbacks, over: over);
