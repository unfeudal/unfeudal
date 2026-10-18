// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/tokens.dart';
import '../../ssh/ssh_connector.dart';

/// An org host's startup command, shown in full before it runs.
class StartupCommandDialog extends StatelessWidget {
  const StartupCommandDialog({
    super.key,
    required this.hostName,
    required this.command,
  });

  final String hostName;
  final String command;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.startupCommandTitle(hostName)),
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(l.startupCommandBody),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Text(command, style: monoStyle),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('startup-skip'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.startupCommandSkip),
        ),
        FilledButton(
          key: const Key('startup-run'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.startupCommandRun),
        ),
      ],
    );
  }
}

class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({super.key, required this.target});

  final String target;

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void submit() => Navigator.pop(context, _password.text);
    return AlertDialog(
      title: Text(l.sshPasswordTitle(widget.target)),
      content: TextField(
        key: const Key('password-prompt'),
        controller: _password,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: submit,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// Keyboard-interactive prompts; an answer the server does not echo is obscured.
class KeyboardInteractiveDialog extends StatefulWidget {
  const KeyboardInteractiveDialog({
    super.key,
    required this.name,
    required this.instruction,
    required this.prompts,
  });

  final String name;
  final String instruction;
  final List<SshPrompt> prompts;

  @override
  State<KeyboardInteractiveDialog> createState() =>
      _KeyboardInteractiveDialogState();
}

class _KeyboardInteractiveDialogState extends State<KeyboardInteractiveDialog> {
  late final _answers = [
    for (final _ in widget.prompts) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.name.isEmpty ? l.sshPromptsTitle : widget.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          if (widget.instruction.isNotEmpty) Text(widget.instruction),
          for (var i = 0; i < widget.prompts.length; i++)
            TextField(
              controller: _answers[i],
              obscureText: !widget.prompts[i].echo,
              autofocus: i == 0,
              decoration: InputDecoration(
                labelText: widget.prompts[i].text.trim(),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('prompts-ok'),
          onPressed: () =>
              Navigator.pop(context, [for (final c in _answers) c.text]),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
