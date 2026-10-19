// SPDX-License-Identifier: Apache-2.0
import '../crypto/payload_crypto.dart';
import '../crypto/safety_code.dart';
import '../ids.dart';
import '../protocol/item.dart';
import '../util/json_reader.dart';
import 'known_host.dart';

/// Per-device rollback defence: replay marks, host and member pins and
/// approved startup commands, sealed under the userKey. Mark rules live in
/// the client's ledger store.
class Ledger {
  Ledger({
    required this.seq,
    required this.hostPins,
    required this.memberPins,
    required this.startupApprovals,
    this.extra = const {},
  });

  Ledger.empty()
    : seq = {},
      hostPins = {},
      memberPins = {},
      startupApprovals = {},
      extra = const {};

  factory Ledger.fromJson(Object? json) {
    final r = JsonReader(json, 'ledger');
    return Ledger(
      seq: {
        for (final e in r.object('seq').entries)
          _seqKey(e.key): _positive(e.value),
      },
      hostPins: {
        for (final e in r.object('hostPins').entries)
          _uuidKey('hostPins', e.key): KnownHostMeta.fromJson(e.value),
      },
      memberPins: {
        for (final e in r.object('memberPins').entries)
          _uuidKey('memberPins', e.key): _memberPin(e.value),
      },
      startupApprovals: {
        for (final e in r.object('startupApprovals').entries)
          _uuidKey('startupApprovals', e.key): _sha256Base64(e.value),
      },
      extra: r.extra(const {
        'seq',
        'hostPins',
        'memberPins',
        'startupApprovals',
      }),
    );
  }

  /// Keyed by `<itemId>/<part>`.
  final Map<String, int> seq;
  final Map<String, KnownHostMeta> hostPins;
  final Map<String, ({String fingerprint, bool verified})> memberPins;

  /// SHA-256 (base64) of the approved org-host `startupCommand`, by host id.
  final Map<String, String> startupApprovals;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'seq': seq,
    'hostPins': {for (final e in hostPins.entries) e.key: e.value.toJson()},
    'memberPins': {
      for (final e in memberPins.entries)
        e.key: {
          'fingerprint': e.value.fingerprint,
          'verified': e.value.verified,
        },
    },
    'startupApprovals': startupApprovals,
  };

  static final _seqPattern = RegExp(r'^([^/]+)/(meta|secret)$');
  static final _sha256 = RegExp(r'^[A-Za-z0-9+/]{43}=$');

  static String _seqKey(String key) {
    final match = _seqPattern.firstMatch(key);
    if (match == null || !isUuid(match[1]!)) {
      throw const FormatException('ledger.seq: key is not <uuid>/<part>');
    }
    return key;
  }

  static int _positive(Object? value) {
    if (value is! int || value < 1) {
      throw const FormatException('ledger.seq: value must be an integer >= 1');
    }
    return value;
  }

  static String _uuidKey(String map, String key) {
    if (!isUuid(key)) throw FormatException('ledger.$map: key is not a UUID');
    return key;
  }

  static ({String fingerprint, bool verified}) _memberPin(Object? json) {
    final r = JsonReader(json, 'ledger.memberPins');
    final fingerprint = r.req<String>('fingerprint');
    if (!isKeyFingerprint(fingerprint)) {
      throw const FormatException('ledger.memberPins.fingerprint: invalid');
    }
    return (fingerprint: fingerprint, verified: r.flag('verified'));
  }

  static String _sha256Base64(Object? value) {
    if (value is! String || !_sha256.hasMatch(value)) {
      throw const FormatException('ledger.startupApprovals: not a SHA-256');
    }
    return value;
  }
}

final ledgerAad = _localAad('local:ledger');

final keyringAad = _localAad('local:keyring');

PayloadAad _localAad(String itemId) => PayloadAad(
  itemId: itemId,
  part: PayloadPart.meta,
  type: 'ledger',
  scope: ItemScope.personal,
  orgId: null,
  folderId: null,
);
