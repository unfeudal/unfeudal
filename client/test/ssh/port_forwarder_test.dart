// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ssh/port_forwarder.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

class _Echo implements SSHSocket {
  final _back = StreamController<Uint8List>();
  late final _in = StreamController<List<int>>()
    ..stream.listen(
      (d) => _back.add(Uint8List.fromList(d)),
      onDone: _back.close,
    );
  @override
  Stream<Uint8List> get stream => _back.stream;
  @override
  StreamSink<List<int>> get sink => _in.sink;
  @override
  Future<void> get done => _in.done;
  @override
  Future<void> close() => _in.close();
  @override
  void destroy() => _in.close();

  @override
  Future<void> flush() async {}
}

PortForward fwd(int port, {bool low = false}) => PortForward(
  localPort: port,
  remoteHost: 'db.internal',
  remotePort: 5432,
  allowLowPorts: low,
);

void main() {
  test('binds loopback only and pipes both ways', () async {
    final port = await freePort();
    final opened = <String>[];
    final f = PortForwarder((host, p) async {
      opened.add('$host:$p');
      return _Echo();
    });
    final handle = await f.start(fwd(port));
    expect(handle.address, InternetAddress.loopbackIPv4);
    final client = await Socket.connect(InternetAddress.loopbackIPv4, port);
    client.add('ping'.codeUnits);
    expect(
      String.fromCharCodes(
        await client.first.timeout(const Duration(seconds: 2)),
      ),
      'ping',
    );
    expect(opened, ['db.internal:5432']);
    client.destroy();
    await f.stopAll();
  });

  test('a port in use throws PortInUse and is recorded as failed', () async {
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final f = PortForwarder((h, p) async => _Echo());
    await expectLater(
      f.start(fwd(blocker.port)),
      throwsA(isA<PortInUse>().having((e) => e.port, 'port', blocker.port)),
    );
    expect(f.active, isEmpty);
    expect(f.failed[blocker.port], isA<PortInUse>());
    await blocker.close();
  });

  test('a low port without opt-in is refused before binding', () async {
    final f = PortForwarder((h, p) async => _Echo());
    await expectLater(f.start(fwd(80)), throwsArgumentError);
    expect(f.active, isEmpty);
  });

  test(
    'start is idempotent per local port; stop releases it and notifies',
    () async {
      final port = await freePort();
      final f = PortForwarder((h, p) async => _Echo());
      var changes = 0;
      f.addListener(() => changes++);
      await f.start(fwd(port));
      await f.start(fwd(port));
      expect(f.active.keys, [port]);
      await f.stop(port);
      expect(f.active, isEmpty);
      expect(changes, 2);
      await (await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      )).close();
    },
  );

  test(
    'a refused channel ends that connection only; the listener stays',
    () async {
      final port = await freePort();
      final f = PortForwarder(
        (h, p) async => throw StateError('administratively prohibited'),
      );
      await f.start(fwd(port));
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
      await s.drain<void>().timeout(const Duration(seconds: 2));
      expect(f.active.keys, [port]);
      await f.stopAll();
    },
  );
}
