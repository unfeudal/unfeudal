// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/loquet/loquet_memory.dart';
import 'src/session/biometrics.dart';
import 'src/session/session_store.dart';
import 'src/settings/settings.dart';
import 'src/storage/local_mirror.dart';
import 'src/window/single_instance.dart';
import 'src/window/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = (await getApplicationSupportDirectory()).path;
  late final WindowChrome chrome;
  final instance = await SingleInstance.claim(
    support,
    onKnock: () => unawaited(chrome.bringToFront()),
  );
  if (instance == null) exit(0); // the running instance came forward
  chrome = await WindowChrome.start();
  final state = AppState(
    sessions: SessionStore(FlutterSecureKv()),
    biometrics: Platform.isWindows || Platform.isMacOS
        ? const ChannelBiometricBackend()
        : null,
    settingsStore: SettingsStore(File(p.join(support, 'settings.json'))),
    openMirror: (userId) async =>
        LocalMirror.open(p.join(support, 'mirror-$userId.sqlite')),
    loquetMemory: await LoquetMemory.load(
      File(p.join(support, 'loquet.json')),
      now: DateTime.now(),
    ),
  )..loquet.life = true;
  await state.boot();
  runApp(UnfeudalApp(state: state, chrome: chrome));
}
