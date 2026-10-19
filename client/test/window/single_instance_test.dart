// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/window/single_instance.dart';

void main() {
  test(
    'a second launch knocks: the first one is shown, the second gets null',
    () async {
      final dir = await Directory.systemTemp.createTemp('instance');
      addTearDown(() => dir.delete(recursive: true));
      final shown = Completer<void>();
      final first = await SingleInstance.claim(
        dir.path,
        onKnock: shown.complete,
      );
      expect(first, isNotNull);
      expect(await SingleInstance.claim(dir.path, onKnock: () {}), isNull);
      await shown.future.timeout(const Duration(seconds: 2));
      await first!.close();
    },
  );

  test('a stale port file does not block the launch', () async {
    final dir = await Directory.systemTemp.createTemp('instance');
    addTearDown(() => dir.delete(recursive: true));
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await File('${dir.path}/instance.port').writeAsString('${unused.port}');
    await unused.close();
    final claimed = await SingleInstance.claim(dir.path, onKnock: () {});
    expect(claimed, isNotNull);
    await claimed!.close();
  });
}
