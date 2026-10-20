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
  InviteCreated(
    this.id,
    this.email,
    this.role,
    this.expiresAt,
    this.link,
    this.file,
    this.mailSent,
  );

  factory InviteCreated.fromJson(Object? json) {
    final body = JsonReader(json, 'invite created');
    final r = JsonReader(body.object('invite'), 'invite');
    return InviteCreated(
      r.uuid('id'),
      r.req<String>('email'),
      _role(r),
      r.time('expiresAt'),
      r.req<String>('link'),
      r.req<String>('file'),
      body.req<bool>('mailSent'),
    );
  }

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

  factory PendingInvite.fromJson(Object? json) {
    final r = JsonReader(json, 'pending invite');
    return PendingInvite(
      r.uuid('id'),
      r.req<String>('email'),
      _role(r),
      r.uuid('createdBy'),
      r.time('createdAt'),
      r.time('expiresAt'),
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
  AdminUser(
    this.id,
    this.email,
    this.disabled,
    this.isInstanceOwner,
    this.createdAt,
  );

  factory AdminUser.fromJson(Object? json) {
    final r = JsonReader(json, 'admin user');
    return AdminUser(
      r.uuid('id'),
      r.req<String>('email'),
      r.req<bool>('disabled'),
      r.req<bool>('isInstanceOwner'),
      r.time('createdAt'),
    );
  }

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

  factory AdminOrg.fromJson(Object? json) {
    final r = JsonReader(json, 'admin org');
    final owners = r.req<List<Object?>>('owners');
    if (!owners.every((o) => o is String)) {
      throw const FormatException('admin org.owners: not strings');
    }
    return AdminOrg(
      r.uuid('id'),
      r.req<String>('name'),
      owners.cast<String>(),
      r.req<int>('memberCount'),
      r.req<int>('storageBytes'),
      r.optTime('lastActivityAt'),
    );
  }

  final String id;
  final String name;
  final List<String> owners;
  final int memberCount;
  final int storageBytes;
  final DateTime? lastActivityAt;
}
