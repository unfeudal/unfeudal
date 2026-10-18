// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/session/session_store.dart';
import 'src/settings/settings.dart';
import 'src/storage/local_mirror.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = (await getApplicationSupportDirectory()).path;
  final state = AppState(
    sessions: SessionStore(FlutterSecureKv()),
    settingsStore: SettingsStore(File(p.join(support, 'settings.json'))),
    openMirror: (userId) async =>
        LocalMirror.open(p.join(support, 'mirror-$userId.sqlite')),
  );
  await state.boot();
  runApp(UnfeudalApp(state: state));
}
