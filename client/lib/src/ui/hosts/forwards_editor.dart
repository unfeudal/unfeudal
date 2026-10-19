// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
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

  /// One problem per row, null when the row is fine.
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
    final mono = monoStyle.copyWith(fontSize: 13);
    Widget input(String key, TextEditingController c, String hint) => TextField(
      key: Key(key),
      controller: c,
      enabled: widget.enabled,
      style: mono,
      onChanged: (_) => _changed(),
      decoration: InputDecoration(hintText: hint, isDense: true),
    );
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
              Row(
                spacing: 6,
                children: [
                  SizedBox(
                    width: 80,
                    child: input(
                      'forward-local-$i',
                      _rows[i].local,
                      l.forwardLocalPort,
                    ),
                  ),
                  Text('→', style: mono.copyWith(color: colors.muted)),
                  Expanded(
                    child: input(
                      'forward-host-$i',
                      _rows[i].host,
                      l.forwardRemoteHost,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: input(
                      'forward-remote-$i',
                      _rows[i].remote,
                      l.forwardRemotePort,
                    ),
                  ),
                  IconButton(
                    key: Key('forward-remove-$i'),
                    tooltip: l.forwardRemove,
                    iconSize: 14,
                    onPressed: widget.enabled
                        ? () {
                            _rows.removeAt(i).dispose();
                            _changed();
                          }
                        : null,
                    icon: const Icon(UfIcons.x),
                  ),
                ],
              ),
              Row(
                spacing: 6,
                children: [
                  Switch(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    key: Key('forward-auto-$i'),
                    value: _rows[i].autoStart,
                    onChanged: widget.enabled
                        ? (v) {
                            _rows[i].autoStart = v;
                            _changed();
                          }
                        : null,
                  ),
                  Flexible(child: Text(l.forwardAutoStart, style: small)),
                  if ((_rows[i].localPort ?? 1024) < 1024) ...[
                    Checkbox(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      key: Key('forward-low-$i'),
                      value: _rows[i].allowLow,
                      onChanged: widget.enabled
                          ? (v) {
                              _rows[i].allowLow = v ?? false;
                              _changed();
                            }
                          : null,
                    ),
                    Flexible(child: Text(l.forwardAllowLow, style: small)),
                  ],
                ],
              ),
              if (problems[i] case final problem?)
                Text(problem, style: small.copyWith(color: colors.danger)),
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
