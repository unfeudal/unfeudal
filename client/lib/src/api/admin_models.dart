// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

OrgRole? _role(JsonReader r) => switch (r.opt<String>('role')) {
  null => null,
  final wire =>
    OrgRole.values.asNameMap()[wire] ??
        (throw FormatException('${r.what}.role: unknown role')),
};

/// A new invite (org or instance): the link and file are shown once.
class InviteCreated {
  InviteCreated({
    required this.id,
    required this.email,
    required this.role,
    required this.expiresAt,
    required this.link,
    required this.file,
    required this.mailSent,
  });

  factory InviteCreated.fromJson(Object? json) {
    final body = JsonReader(json, 'invite created');
    final r = JsonReader(body.object('invite'), 'invite');
    return InviteCreated(
      id: r.uuid('id'),
      email: r.req<String>('email'),
      role: _role(r),
      expiresAt: r.time('expiresAt'),
      link: r.req<String>('link'),
      file: r.req<String>('file'),
      mailSent: body.req<bool>('mailSent'),
    );
  }

  final String id;
  final String email;

  /// Null for an instance invite.
  final OrgRole? role;
  final DateTime expiresAt;
  final String link;
  final String file;
  final bool mailSent;
}

class PendingInvite {
  PendingInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
  });

  factory PendingInvite.fromJson(Object? json) {
    final r = JsonReader(json, 'pending invite');
    return PendingInvite(
      id: r.uuid('id'),
      email: r.req<String>('email'),
      role: _role(r),
      createdBy: r.uuid('createdBy'),
      createdAt: r.time('createdAt'),
      expiresAt: r.time('expiresAt'),
    );
  }

  final String id;
  final String email;
  final OrgRole? role;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
}

class AdminUser {
  AdminUser({
    required this.id,
    required this.email,
    required this.disabled,
    required this.isInstanceOwner,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Object? json) {
    final r = JsonReader(json, 'admin user');
    return AdminUser(
      id: r.uuid('id'),
      email: r.req<String>('email'),
      disabled: r.req<bool>('disabled'),
      isInstanceOwner: r.req<bool>('isInstanceOwner'),
      createdAt: r.time('createdAt'),
    );
  }

  final String id;
  final String email;
  final bool disabled;
  final bool isInstanceOwner;
  final DateTime createdAt;
}

class AdminOrg {
  AdminOrg({
    required this.id,
    required this.name,
    required this.owners,
    required this.memberCount,
    required this.storageBytes,
    required this.lastActivityAt,
  });

  factory AdminOrg.fromJson(Object? json) {
    final r = JsonReader(json, 'admin org');
    final owners = r.req<List<Object?>>('owners');
    if (!owners.every((o) => o is String)) {
      throw const FormatException('admin org.owners: not strings');
    }
    return AdminOrg(
      id: r.uuid('id'),
      name: r.req<String>('name'),
      owners: owners.cast<String>(),
      memberCount: r.req<int>('memberCount'),
      storageBytes: r.req<int>('storageBytes'),
      lastActivityAt: r.optTime('lastActivityAt'),
    );
  }

  final String id;
  final String name;
  final List<String> owners;
  final int memberCount;
  final int storageBytes;
  final DateTime? lastActivityAt;
}
