// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../../design/dialog.dart';
import '../describe_error.dart';

/// This account's devices, the current one marked, each other one revocable; Réglages › Appareils.
class DeviceList extends StatefulWidget {
  const DeviceList({super.key});

  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
  late Future<List<Device>> _devices = AppScope.read(context).loadDevices();
  String? _error;

  Future<void> _revoke(Device device) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    if (device.id == state.stored?.deviceId) {
      final yes = await confirmDanger(
        context,
        question: l.deviceRevokeSelf,
        action: l.deviceRevoke,
      );
      if (!yes) return;
    }
    try {
      await state.revokeDevice(device.id);
      if (!mounted || state.stored == null) {
        return; // revoking this device signed out
      }
      final reloaded = state.loadDevices();
      setState(() {
        _devices = reloaded;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final dates = MaterialLocalizations.of(context);
    return FutureBuilder(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.error case final Exception e) {
          return Center(child: Text(describeError(l, e)));
        }
        final devices = snapshot.data;
        if (devices == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            if (_error case final error?)
              Text(error, style: TextStyle(color: colors.danger)),
            for (final d in devices)
              _DeviceRow(
                key: ValueKey(d.id),
                device: d,
                lastSeen: l.deviceLastSeen(
                  dates.formatMediumDate(d.lastSeenAt.toLocal()),
                ),
                onRevoke: () => _revoke(d),
              ),
          ],
        );
      },
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.lastSeen,
    required this.onRevoke,
  });

  final Device device;
  final String lastSeen;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final revoked = device.revokedAt != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ItemRow(
        icon: UfIcons.desktop,
        title: device.name,
        subtitle: lastSeen,
        dimmed: revoked,
        trailing: [
          if (device.current)
            Container(
              key: Key('device-current-${device.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.okSoft,
                borderRadius: UfRadius.key,
              ),
              child: Text(
                l.deviceCurrent,
                style: TextStyle(
                  color: colors.ok,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (revoked)
            UfTag(l.deviceRevoked)
          else
            TextButton(
              key: Key('revoke-${device.id}'),
              style: dangerQuietStyle(colors).merge(smallButton),
              onPressed: onRevoke,
              child: Text(l.deviceRevoke),
            ),
        ],
      ),
    );
  }
}
