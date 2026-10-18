// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';

/// The devices of the account; revoking this one signs out (asked first). Allowed in read-only mode.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<Device>> _devices = AppScope.read(context).loadDevices();
  String? _error;

  Future<void> _revoke(Device device) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    if (device.id == state.stored?.deviceId) {
      final yes = await showUfDialog<bool>(
        context,
        (dialog) => AlertDialog(
          content: Text(l.deviceRevokeSelf),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const Key('confirm-yes'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(l.deviceRevoke),
            ),
          ],
        ),
      );
      if (yes != true) return;
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
    return Scaffold(
      appBar: AppBar(title: Text(l.devicesTitle)),
      body: FutureBuilder(
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
            padding: const EdgeInsets.all(20),
            children: [
              if (_error case final error?)
                Text(error, style: TextStyle(color: colors.danger)),
              for (final d in devices)
                ListTile(
                  enabled: d.revokedAt == null,
                  leading: const Icon(UfIcons.devices),
                  title: Text(d.name),
                  subtitle: Text(
                    l.deviceLastSeen(
                      dates.formatMediumDate(d.lastSeenAt.toLocal()),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      if (d.current)
                        Chip(
                          key: Key('device-current-${d.id}'),
                          label: Text(l.deviceCurrent),
                        ),
                      if (d.revokedAt != null)
                        Text(
                          l.deviceRevoked,
                          style: TextStyle(color: colors.muted),
                        )
                      else
                        TextButton(
                          key: Key('revoke-${d.id}'),
                          onPressed: () => _revoke(d),
                          child: Text(l.deviceRevoke),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
