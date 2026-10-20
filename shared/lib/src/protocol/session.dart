// SPDX-License-Identifier: Apache-2.0
import '../crypto/account.dart';
import '../time.dart';
import '../util/json_reader.dart';

/// Login, setup and recovery response.
class Session {
  Session({
    required this.userId,
    required this.deviceId,
    required this.accessToken,
    required this.refreshToken,
    required this.bundle,
    required this.bundleVersion,
    required this.isInstanceOwner,
    this.extra = const {},
  });

  factory Session.fromJson(Object? json) {
    final r = JsonReader(json, 'session');
    return Session(
      userId: r.uuid('userId'),
      deviceId: r.uuid('deviceId'),
      accessToken: r.text('accessToken', max: 1024),
      refreshToken: r.text('refreshToken', max: 1024),
      bundle: AccountBundle.fromJson(r.object('bundle')),
      bundleVersion: r.integer('bundleVersion'),
      isInstanceOwner: r.flag('isInstanceOwner'),
      extra: r.extra(const {
        'userId',
        'deviceId',
        'accessToken',
        'refreshToken',
        'bundle',
        'bundleVersion',
        'isInstanceOwner',
      }),
    );
  }

  final String userId;
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final AccountBundle bundle;
  final int bundleVersion;
  final bool isInstanceOwner;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'userId': userId,
    'deviceId': deviceId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'bundle': bundle.toJson(),
    'bundleVersion': bundleVersion,
    'isInstanceOwner': isInstanceOwner,
  };
}

/// `POST /token/refresh` response.
class TokenPair {
  TokenPair(this.accessToken, this.refreshToken);

  factory TokenPair.fromJson(Object? json) {
    final r = JsonReader(json, 'tokens');
    return TokenPair(
      r.text('accessToken', max: 1024),
      r.text('refreshToken', max: 1024),
    );
  }

  final String accessToken;
  final String refreshToken;

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}

const devicePlatforms = [
  'windows',
  'macos',
  'linux',
  'android',
  'ios',
  'other',
];

class Device {
  Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    this.revokedAt,
    required this.current,
    this.extra = const {},
  });

  factory Device.fromJson(Object? json) {
    final r = JsonReader(json, 'device');
    return Device(
      id: r.uuid('id'),
      name: r.text('name', max: 100, required: true),
      // Kept as sent; the server validates it against devicePlatforms.
      platform: r.text('platform', max: 32),
      createdAt: r.time('createdAt'),
      lastSeenAt: r.time('lastSeenAt'),
      revokedAt: r.optTime('revokedAt'),
      current: r.flag('current'),
      extra: r.extra(const {
        'id',
        'name',
        'platform',
        'createdAt',
        'lastSeenAt',
        'revokedAt',
        'current',
      }),
    );
  }

  final String id;
  final String name;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
  final bool current;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'platform': platform,
    'createdAt': iso(createdAt),
    'lastSeenAt': iso(lastSeenAt),
    'revokedAt': revokedAt == null ? null : iso(revokedAt!),
    'current': current,
  };
}
