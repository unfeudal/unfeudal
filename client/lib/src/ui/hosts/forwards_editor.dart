// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/choices.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';

/// Edits a host's port forwards. Reports the list, or null while any row is invalid, uses a low port
/// without the opt-in, or repeats a local port.
class ForwardsEditor extends StatefulWidget {
  const ForwardsEditor({
    super.key,
    required this.forwards,
    required this.onChanged,
    this.enabled = true,
  });

  final List<PortForward> forwards;
  final ValueChanged<List<PortForward>?> onChanged;
  final bool enabled;

  @override
  State<ForwardsEditor> createState() => _ForwardsEditorState();
}

class _Row {
  _Row([PortForward? f])
    : local = TextEditingController(text: f == null ? '' : '${f.localPort}'),
      host = TextEditingController(text: f?.remoteHost ?? ''),
      remote = TextEditingController(text: f == null ? '' : '${f.remotePort}'),
      autoStart = f?.autoStart ?? false,
      allowLow = f?.allowLowPorts ?? false,
      extra = f?.extra ?? const {};

  final TextEditingController local, host, remote;
  bool autoStart, allowLow;

  /// Unknown fields of a loaded forward, written back as they were.
  final Map<String, Object?> extra;

  int? get localPort => int.tryParse(local.text.trim());

  PortForward? parse() {
    final localPort = this.localPort;
    final remotePort = int.tryParse(remote.text.trim());
    if (localPort == null || remotePort == null) return null;
    try {
      return PortForward.fromJson({
        ...extra,
        'localPort': localPort,
        'remoteHost': host.text.trim(),
        'remotePort': remotePort,
        'autoStart': autoStart,
        if (allowLow) 'allowLowPorts': true,
      });
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    for (final c in [local, host, remote]) {
      c.dispose();
    }
  }
}

class _ForwardsEditorState extends State<ForwardsEditor> {
  late final _rows = [for (final f in widget.forwards) _Row(f)];

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // One problem per row, null when the row is fine.
  List<String?> _problems(AppLocalizations l) {
    final parsed = [for (final r in _rows) r.parse()];
    final problems = [
      for (final p in parsed) p == null ? l.fieldInvalid : null,
    ];
    final valid = [
      for (var i = 0; i < parsed.length; i++)
        if (parsed[i] != null) i,
    ];
    for (final issue in validateForwards([for (final i in valid) parsed[i]!])) {
      problems[valid[issue.index]] ??= switch (issue.kind) {
        ForwardIssueKind.lowPortNotAllowed => l.forwardLowPort,
        ForwardIssueKind.duplicateLocalPort => l.forwardDuplicate,
      };
    }
    return problems;
  }

  void _changed() {
    final l = AppLocalizations.of(context);
    setState(() {});
    widget.onChanged(
      _problems(l).every((p) => p == null)
          ? [for (final r in _rows) r.parse()!]
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final small = Theme.of(context).textTheme.labelSmall!;
    final problems = _problems(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(l.hostForwards, style: small.copyWith(color: colors.muted)),
        for (var i = 0; i < _rows.length; i++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              _ForwardEndpoints(
                index: i,
                row: _rows[i],
                enabled: widget.enabled,
                onChanged: _changed,
                onRemove: () {
                  _rows.removeAt(i).dispose();
                  _changed();
                },
              ),
              _ForwardOptions(
                index: i,
                row: _rows[i],
                enabled: widget.enabled,
                onChanged: _changed,
              ),
              if (problems[i] case final problem?) UfErrorLine(problem),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('forward-add'),
            onPressed: widget.enabled && _rows.length < PayloadLimits.forwards
                ? () {
                    _rows.add(_Row());
                    _changed();
                  }
                : null,
            child: Text(l.forwardAdd),
          ),
        ),
      ],
    );
  }
}

class _ForwardEndpoints extends StatelessWidget {
  const _ForwardEndpoints({
    required this.index,
    required this.row,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _Row row;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    Widget input(String key, TextEditingController c, String hint) => TextField(
      key: Key(key),
      controller: c,
      enabled: enabled,
      style: monoField,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(hintText: hint),
    );
    return Row(
      spacing: 6,
      children: [
        SizedBox(
          width: 80,
          child: input('forward-local-$index', row.local, l.forwardLocalPort),
        ),
        Text('→', style: monoField.copyWith(color: colors.muted)),
        Expanded(
          child: input('forward-host-$index', row.host, l.forwardRemoteHost),
        ),
        SizedBox(
          width: 80,
          child: input(
            'forward-remote-$index',
            row.remote,
            l.forwardRemotePort,
          ),
        ),
        IconButton(
          key: Key('forward-remove-$index'),
          tooltip: l.forwardRemove,
          onPressed: enabled ? onRemove : null,
          icon: const Icon(UfIcons.x),
        ),
      ],
    );
  }
}

class _ForwardOptions extends StatelessWidget {
  const _ForwardOptions({
    required this.index,
    required this.row,
    required this.enabled,
    required this.onChanged,
  });

  final int index;
  final _Row row;
  final bool enabled;
  final VoidCallback onChanged;

  void _setAutoStart(bool value) {
    row.autoStart = value;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final small = Theme.of(context).textTheme.labelSmall!;
    return Row(
      spacing: 6,
      children: [
        Flexible(
          // the label toggles too
          child: GestureDetector(
            onTap: enabled ? () => _setAutoStart(!row.autoStart) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                UfSwitch(
                  key: Key('forward-auto-$index'),
                  value: row.autoStart,
                  onChanged: enabled ? _setAutoStart : null,
                ),
                Flexible(child: Text(l.forwardAutoStart, style: small)),
              ],
            ),
          ),
        ),
        if ((row.localPort ?? 1024) < 1024)
          Flexible(
            child: UfCheckboxRow(
              key: Key('forward-low-$index'),
              value: row.allowLow,
              label: l.forwardAllowLow,
              onChanged: enabled
                  ? (v) {
                      row.allowLow = v;
                      onChanged();
                    }
                  : null,
            ),
          ),
      ],
    );
  }
}
