// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:unfeudal_shared/unfeudal_shared.dart';

/// Writes the account bundle fixture once; the output is frozen, never hand-edited.
Future<void> main() async {
  final acc = await AccountCrypto(
    kdf: KdfParams.testing,
    allowTestingKdf: true,
  ).create('fixture-password');
  File('test/fixtures/v0/account_bundle.json')
      .writeAsStringSync('${jsonEncode(acc.bundle.toJson())}\n');
  stdout.writeln('written');
}
