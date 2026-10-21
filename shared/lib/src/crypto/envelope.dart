// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import '../bytes.dart';
import '../ids.dart';
import '../util/json_reader.dart';

enum PayloadPart { meta, secret }

/// An AEAD ciphertext with its version, algorithm and key label. A newer
/// version or algorithm parses and keeps its bytes; it is refused only when
/// opened.
class Envelope {
  Envelope({
    required this.v,
    required this.alg,
    required this.keyId,
    required this.nonce,
    required this.ct,
    this.extra = const {},
  });

  factory Envelope.fromJson(Object? json) {
    final r = JsonReader(json, 'envelope');
    final keyId = r.text('keyId', max: 256);
    if (keyId.contains('\u0000')) {
      throw const FormatException('envelope.keyId: contains NUL');
    }
    final envelope = Envelope(
      v: r.integer('v'),
      alg: r.text('alg', max: 64),
      keyId: keyId,
      nonce: r.bytes('nonce'),
      ct: r.bytes('ct'),
      extra: r.extra(_known),
    );
    if (envelope.isSupported &&
        (envelope.nonce.length != nonceLength ||
            envelope.ct.length < tagLength)) {
      throw const FormatException('envelope: bad nonce or ct length');
    }
    return envelope;
  }

  static const xchacha = 'xchacha20poly1305';
  static const nonceLength = 24;
  static const tagLength = 16;
  static const _known = {'v', 'alg', 'keyId', 'nonce', 'ct'};

  final int v;
  final String alg;
  final String keyId;
  final Uint8List nonce;
  final Uint8List ct;
  final Map<String, Object?> extra;

  bool get isSupported => v == 1 && alg == xchacha;

  Map<String, Object?> toJson() => {
    ...extra,
    'v': v,
    'alg': alg,
    'keyId': keyId,
    'nonce': b64(nonce),
    'ct': b64(ct),
  };
}

/// The envelope key labels; each one is bound into the AEAD data.
abstract final class KeyIds {
  static const master = 'master';
  static const recovery = 'recovery';
  static const userX25519 = 'user-x25519';
  static const user = 'user';
  static const enroll = 'enroll';
  static const export = 'export';
  static const biometric = 'biometric';

  static String folder(String folderId, int version, PayloadPart part) =>
      'folder:$folderId:v$version:${part.name}';

  static String sealed(String purpose) => 'sealed:$purpose';

  static final _folderPattern = RegExp(
    r'^folder:([^:]+):v([1-9][0-9]{0,8}):(meta|secret)$',
  );

  /// Null when [keyId] is not a folder key label.
  static ({String folderId, int version, PayloadPart part})? parseFolder(
    String keyId,
  ) {
    final match = _folderPattern.firstMatch(keyId);
    if (match == null || !isUuid(match[1]!)) return null;
    return (
      folderId: match[1]!,
      version: int.parse(match[2]!),
      part: PayloadPart.values.byName(match[3]!),
    );
  }
}
