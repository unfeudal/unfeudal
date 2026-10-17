// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

final testUserId = newId();
final testDeviceId = newId();

Envelope fakeEnvelope([String keyId = 'user']) => Envelope.fromJson({
  'v': 1,
  'alg': 'xchacha20poly1305',
  'keyId': keyId,
  'nonce': b64(Uint8List(24)),
  'ct': b64(Uint8List(16)),
});

/// A wire item whose payloads are not meant to be opened (mirror and engine tests).
Item wireItem(
  String id, {
  int revision = 1,
  String type = 'host',
  bool deleted = false,
  bool purged = false,
  String? folderId,
  String? updatedDevice,
}) => Item.fromJson({
  'id': id,
  'type': type,
  'scope': 'personal',
  'orgId': null,
  'folderId': folderId,
  'schemaVersion': 1,
  'revision': revision,
  'deleted': deleted || purged,
  if (purged) 'purged': true,
  'meta': purged ? null : fakeEnvelope().toJson(),
  'secret': null,
  'createdAt': iso(DateTime.utc(2026, 10, 1)),
  'updatedAt': iso(DateTime.utc(2026, 10, 14)),
  'updatedBy': testUserId,
  'updatedDevice': updatedDevice ?? testDeviceId,
});
