// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/tokens.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';
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
    final colors = UfColors.of(context);
    return UfDialog(
      leading: const LoquetSpot(
        placement: LoquetPlacement.dialog,
        mood: LoquetMood.concerned,
      ),
      title: l.startupCommandTitle(hostName),
      message: l.startupCommandBody,
      actions: [
        TextButton(
          key: const Key('startup-skip'),
          style: quietButtonStyle(colors),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.startupCommandSkip),
        ),
        FilledButton(
          key: const Key('startup-run'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.startupCommandRun),
        ),
      ],
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.field,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              command,
              style: monoStyle.copyWith(fontSize: 13),
            ),
          ),
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
    return UfDialog(
      width: 440,
      title: l.sshPasswordTitle(widget.target),
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context)),
        FilledButton(
          onPressed: submit,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
      children: [
        TextField(
          key: const Key('password-prompt'),
          controller: _password,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => submit(),
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
    return UfDialog(
      width: 440,
      title: widget.name.isEmpty ? l.sshPromptsTitle : widget.name,
      message: widget.instruction.isEmpty ? null : widget.instruction,
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context)),
        FilledButton(
          key: const Key('prompts-ok'),
          onPressed: () =>
              Navigator.pop(context, [for (final c in _answers) c.text]),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
      children: [
        for (var i = 0; i < widget.prompts.length; i++)
          UfField(
            label: widget.prompts[i].text.trim(),
            child: TextField(
              controller: _answers[i],
              obscureText: !widget.prompts[i].echo,
              autofocus: i == 0,
            ),
          ),
      ],
    );
  }
}
