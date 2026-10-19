// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../session/lock_machine.dart';

/// What happened in the app, for observers (Loquet, audit). Consumers switch with a default case.
sealed class AppEvent {
  const AppEvent();
}

final class Unlocked extends AppEvent {
  const Unlocked({this.displayName});
  final String? displayName;
}

final class LockScreenStateChanged extends AppEvent {
  const LockScreenStateChanged(this.state);
  final LockScreenState state;
}

final class UnlockFailed extends AppEvent {
  const UnlockFailed({required this.consecutive});
  final int consecutive;
}

final class ConnectStarted extends AppEvent {
  const ConnectStarted({required this.hostId});
  final String hostId;
}

final class ConnectSucceeded extends AppEvent {
  const ConnectSucceeded({
    required this.hostId,
    this.user,
    this.tags = const [],
  });
  final String hostId;
  final String? user;
  final List<String> tags;
}

final class ConnectFailed extends AppEvent {
  const ConnectFailed({required this.hostId, required this.error});
  final String hostId;
  final Object error;
}

final class HostKeyChanged extends AppEvent {
  const HostKeyChanged({required this.hostId});
  final String hostId;
}

final class WentOffline extends AppEvent {
  const WentOffline();
}

final class CameOnline extends AppEvent {
  const CameOnline();
}

final class VaultLocked extends AppEvent {
  const VaultLocked();
}

final class UserIdle extends AppEvent {
  const UserIdle();
}

final class ThemeChanged extends AppEvent {
  const ThemeChanged({required this.mode});
  final ThemeMode mode;
}

final class HostCreated extends AppEvent {
  const HostCreated({
    required this.hostId,
    required this.name,
    required this.total,
  });
  final String hostId;
  final String name;
  final int total;
}

final class DeviceAdded extends AppEvent {
  const DeviceAdded({required this.activeDevices});
  final int activeDevices;
}

final class LoquetClicked extends AppEvent {
  const LoquetClicked();
}

final class JumpUsed extends AppEvent {
  const JumpUsed({required this.hostId, required this.hopIds});
  final String hostId;

  /// Outermost first.
  final List<String> hopIds;
}

final class ForwardStarted extends AppEvent {
  const ForwardStarted({required this.hostId, required this.forward});
  final String hostId;
  final PortForward forward;
}

final class ForwardStopped extends AppEvent {
  const ForwardStopped({required this.hostId, required this.localPort});
  final String hostId;
  final int localPort;
}

final class ForwardFailed extends AppEvent {
  const ForwardFailed({
    required this.hostId,
    required this.localPort,
    required this.error,
  });
  final String hostId;
  final int localPort;
  final Object error;
}

final class SnippetInserted extends AppEvent {
  const SnippetInserted({required this.snippetId});
  final String snippetId;
}
