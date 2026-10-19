// SPDX-License-Identifier: Apache-2.0
import 'dart:math';
import 'dart:typed_data';

final _random = Random.secure();

Uint8List secureBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));
