// SPDX-License-Identifier: Apache-2.0
part of 'host_editor_panel.dart';

mixin _HostFormFields on State<HostEditorPanel> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _user = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  final _startup = TextEditingController();
  int? _port;
  String? _identityId;
  String? _folderId;
  String? _jumpHostId;
  IdentityMode _identityMode = IdentityMode.shared;

  final _problems = <String, String>{};

  VaultEntry? get _entry => widget.hostId == null
      ? null
      : AppScope.read(context).vault!.entry(widget.hostId!);

  String? get _orgId => _entry?.orgId ?? widget.orgId;

  String? _sourceOf(AppLocalizations l, ResolvedHost? resolved, String field) =>
      switch (resolved?.sources[field]) {
        null => null,
        'default' => l.hostDefault,
        final String folder => l.hostInherited(
          AppScope.read(context).vault!.entry(folder)?.name ?? '',
        ),
      };

  // An empty inheritable field shows the resolved value as a hint and its source under it.
  Widget _textField({
    required String key,
    required TextEditingController controller,
    required String label,
    required String problemKey,
    required bool editable,
    ResolvedHost? resolved,
    Object? resolvedValue,
    bool inheritable = false,
    int lines = 1,
    bool mono = false,
  }) {
    final l = AppLocalizations.of(context);
    final inherits = inheritable && controller.text.trim().isEmpty;
    final decoration = InputDecoration(
      hintText: inherits && resolvedValue != null ? '$resolvedValue' : null,
    );
    return UfField(
      label: label,
      source: inherits ? _sourceOf(l, resolved, problemKey) : null,
      error: _problems[problemKey],
      child: TextField(
        key: Key(key),
        controller: controller,
        readOnly: !editable,
        maxLines: lines,
        onChanged: inheritable ? (_) => setState(() {}) : null,
        style: mono ? monoField : null,
        decoration: editable
            ? decoration
            : readOnlyDecoration(context, decoration),
      ),
    );
  }

  Widget _addressFields(
    AppLocalizations l, {
    required bool editable,
    required ResolvedHost? resolved,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      _textField(
        key: 'host-name',
        controller: _name,
        label: l.hostName,
        problemKey: 'name',
        editable: editable,
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Expanded(
            flex: 2,
            child: _textField(
              key: 'host-address',
              controller: _address,
              label: l.hostAddress,
              problemKey: 'address',
              editable: editable,
            ),
          ),
          Expanded(
            child: UfField(
              label: l.hostPort,
              source: _port == null ? _sourceOf(l, resolved, 'port') : null,
              error: _problems['port'],
              child: UfNumberField(
                key: const Key('host-port'),
                value: _port,
                min: 1,
                width: double.infinity,
                placeholder: resolved?.port,
                onChanged: editable
                    ? (port) => setState(() => _port = port)
                    : null,
              ),
            ),
          ),
        ],
      ),
      _textField(
        key: 'host-user',
        controller: _user,
        label: l.hostUser,
        problemKey: 'user',
        editable: editable,
        resolved: resolved,
        inheritable: true,
        resolvedValue: resolved?.user,
      ),
    ],
  );

  List<Widget> _identityFields(
    AppLocalizations l, {
    required bool editable,
    required ResolvedHost? resolved,
  }) {
    final orgId = _orgId;
    final identities = AppScope.read(context).vault!
        .usableOfKind(ItemKind.identity, orgId: orgId);
    return [
      entryPicker(
        key: 'host-identity',
        label: l.hostIdentity,
        none: l.hostDefault,
        entries: identities,
        value: _identityId,
        source: _identityId == null
            ? _sourceOf(l, resolved, 'identityId')
            : null,
        onChanged: editable ? (v) => setState(() => _identityId = v) : null,
      ),
      if (_newIdentityPlace() case final place? when editable)
        _newIdentityButtons(l, place),
      if (orgId != null)
        Column(
          key: const Key('host-identity-mode'),
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            for (final (mode, label) in [
              (IdentityMode.shared, l.hostIdentityShared),
              (IdentityMode.perMember, l.hostIdentityPerMember),
            ])
              UfRadio<IdentityMode>(
                key: Key('identity-mode-${mode.name}'),
                value: mode,
                groupValue: _identityMode,
                label: label,
                onChanged: editable
                    ? (mode) => setState(() => _identityMode = mode)
                    : null,
              ),
          ],
        ),
      if (orgId != null &&
          _identityMode == IdentityMode.perMember &&
          widget.hostId != null)
        HostBindingField(hostId: widget.hostId!),
    ];
  }

  // Generate, import or add a password into [place]; the new identity becomes the host's.
  Widget _newIdentityButtons(AppLocalizations l, IdentityPlace place) => Wrap(
    key: const Key('host-identity-new'),
    spacing: 4,
    children: [
      for (final (key, label, show) in [
        ('host-identity-generate', l.keyGenerate, showGenerateKey),
        ('host-identity-import', l.keyImport, showImportKey),
        ('host-identity-password', l.keyPassword, showAddPassword),
      ])
        TextButton(
          key: Key(key),
          style: smallButton,
          onPressed: () async {
            final id = await show(context, place);
            if (id != null && mounted) setState(() => _identityId = id);
          },
          child: Text(label),
        ),
    ],
  );
  // A personal host's new identity is personal; an org host's goes to its folder, when it is shared there and
  // this account may write it. Null hides the buttons.
  IdentityPlace? _newIdentityPlace() {
    final orgId = _orgId;
    if (orgId == null) return (orgId: null, folderId: null);
    final folderId = _folderId;
    final orgs = AppScope.read(context).orgs;
    return folderId != null &&
            _identityMode == IdentityMode.shared &&
            (orgs?.writer.canEdit(orgId, folderId) ?? false)
        ? (orgId: orgId, folderId: folderId)
        : null;
  }

  List<Widget> _placementFields({
    required bool editable,
    required ResolvedHost? resolved,
  }) {
    final vault = AppScope.read(context).vault!;
    return [
      JumpHostPicker(
        key: const Key('jump-picker'),
        hostId: widget.hostId,
        folderId: _folderId,
        value: _jumpHostId,
        inheritedId: resolved?.jumpHostId,
        inheritedFrom: switch (resolved?.sources['jumpHostId']) {
          null || 'default' || 'host' => null,
          final String folder => vault.entry(folder)?.name,
        },
        onChanged: editable ? (v) => setState(() => _jumpHostId = v) : null,
      ),
    ];
  }

  List<Widget> _detailFields(AppLocalizations l, {required bool editable}) => [
    _textField(
      key: 'host-tags',
      controller: _tags,
      label: l.hostTags,
      problemKey: 'tags',
      editable: editable,
    ),
    _textField(
      key: 'host-notes',
      controller: _notes,
      label: l.hostNotes,
      problemKey: 'notes',
      editable: editable,
      lines: 3,
    ),
    _textField(
      key: 'host-startup',
      controller: _startup,
      label: l.hostStartup,
      problemKey: 'startupCommand',
      editable: editable,
      mono: true,
    ),
  ];
}
