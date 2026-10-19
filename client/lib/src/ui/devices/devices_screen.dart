// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/dialog.dart';
import '../describe_error.dart';
import '../manage_frame.dart';

/// The devices of the account; revoking this one signs out (asked first). Allowed in read-only mode.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.onBack});

  final VoidCallback? onBack;

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
    return ManageFrame(
      title: l.devicesTitle,
      onBack: widget.onBack,
      child: FutureBuilder(
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
      ),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Opacity(
          opacity: revoked ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              spacing: 14,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.field,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                  ),
                  child: Icon(UfIcons.devices, size: 18, color: colors.accent),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        lastSeen,
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (device.current)
                  Container(
                    key: Key('device-current-${device.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.okSoft,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(999),
                      ),
                    ),
                    child: Text(
                      l.deviceCurrent,
                      style: TextStyle(
                        color: colors.ok,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (revoked)
                  Text(l.deviceRevoked, style: TextStyle(color: colors.muted))
                else
                  TextButton(
                    key: Key('revoke-${device.id}'),
                    style: TextButton.styleFrom(foregroundColor: colors.danger),
                    onPressed: onRevoke,
                    child: Text(l.deviceRevoke),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
