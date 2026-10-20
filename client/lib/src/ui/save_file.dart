// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// The path picked in the native "Save as" dialog; null when it is cancelled.
Future<String?> pickSaveLocation(
  String suggestedName, {
  List<XTypeGroup> types = const [],
}) async => (await getSaveLocation(
  suggestedName: suggestedName,
  acceptedTypeGroups: types,
))?.path;

Future<void> writeFileBytes(String path, List<int> bytes) =>
    File(path).writeAsBytes(bytes, flush: true);
