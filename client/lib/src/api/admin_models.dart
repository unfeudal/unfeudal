// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

String _uuid(Object? value) => value is String && isUuid(value)
    ? value
    : throw const FormatException('not a UUID');

OrgRole? _role(Object? value) => switch (value) {
  null => null,
  final String wire => OrgRole.values.firstWhere(
    (r) => r.name == wire,
    orElse: () => throw const FormatException('unknown role'),
  ),
  _ => throw const FormatException('role: not a string'),
};

/// A new invite (org or instance): the link and file are shown once.
class InviteCreated {
  InviteCreated(
    this.id,
    this.email,
    this.role,
    this.expiresAt,
    this.link,
    this.file,
    this.mailSent,
  );

  factory InviteCreated.fromJson(Object? json) => switch (json) {
    {
      'invite': {
        'id': final Object? id,
        'email': final String email,
        'role': final Object? role,
        'expiresAt': final String expiresAt,
        'link': final String link,
        'file': final String file,
      },
      'mailSent': final bool mailSent,
    } =>
      InviteCreated(
        _uuid(id),
        email,
        _role(role),
        parseIso(expiresAt),
        link,
        file,
        mailSent,
      ),
    _ => throw const FormatException('invite: unexpected body'),
  };

  final String id;
  final String email;
  final OrgRole? role; // null for an instance invite
  final DateTime expiresAt;
  final String link;
  final String file;
  final bool mailSent;
}

class PendingInvite {
  PendingInvite(
    this.id,
    this.email,
    this.role,
    this.createdBy,
    this.createdAt,
    this.expiresAt,
  );

  factory PendingInvite.fromJson(Object? json) => switch (json) {
    {
      'id': final Object? id,
      'email': final String email,
      'createdBy': final Object? createdBy,
      'createdAt': final String createdAt,
      'expiresAt': final String expiresAt,
    } =>
      PendingInvite(
        _uuid(id),
        email,
        _role((json as Map)['role']),
        _uuid(createdBy),
        parseIso(createdAt),
        parseIso(expiresAt),
      ),
    _ => throw const FormatException('pending invite: unexpected body'),
  };

  final String id;
  final String email;
  final OrgRole? role;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
}

class AdminUser {
  AdminUser(
    this.id,
    this.email,
    this.disabled,
    this.isInstanceOwner,
    this.createdAt,
  );

  factory AdminUser.fromJson(Object? json) => switch (json) {
    {
      'id': final Object? id,
      'email': final String email,
      'disabled': final bool disabled,
      'isInstanceOwner': final bool isInstanceOwner,
      'createdAt': final String createdAt,
    } =>
      AdminUser(
        _uuid(id),
        email,
        disabled,
        isInstanceOwner,
        parseIso(createdAt),
      ),
    _ => throw const FormatException('admin user: unexpected body'),
  };

  final String id;
  final String email;
  final bool disabled;
  final bool isInstanceOwner;
  final DateTime createdAt;
}

class AdminOrg {
  AdminOrg(
    this.id,
    this.name,
    this.owners,
    this.memberCount,
    this.storageBytes,
    this.lastActivityAt,
  );

  factory AdminOrg.fromJson(Object? json) => switch (json) {
    {
      'id': final Object? id,
      'name': final String name,
      'owners': final List<Object?> owners,
      'memberCount': final int memberCount,
      'storageBytes': final int storageBytes,
      'lastActivityAt': final String? lastActivityAt,
    }
        when owners.every((o) => o is String) =>
      AdminOrg(
        _uuid(id),
        name,
        owners.cast<String>(),
        memberCount,
        storageBytes,
        lastActivityAt == null ? null : parseIso(lastActivityAt),
      ),
    _ => throw const FormatException('admin org: unexpected body'),
  };

  final String id;
  final String name;
  final List<String> owners;
  final int memberCount;
  final int storageBytes;
  final DateTime? lastActivityAt;
}
