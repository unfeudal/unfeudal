// SPDX-License-Identifier: Apache-2.0
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/toast.dart';
import '../busy_action.dart';
import '../describe_error.dart';
import '../fields.dart';
import '../lock/lock_frame.dart';
import 'recovery_kit_view.dart';
import 'setup_screen.dart';

/// A new master password from the recovery key; every device is signed out and a new key is shown.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, this.readKitFile});

  /// The text kit's content; a native "Open" dialog by default (a PDF kit is typed by hand).
  final Future<String?> Function()? readKitFile;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> with BusyAction {
  late final TextEditingController _server;
  late final TextEditingController _email;
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  ({String key, Uri server, String email})? _done;

  // 1: server, e-mail and key; 2: the new password.
  int _step = 1;

  @override
  void initState() {
    super.initState();
    final stored = AppScope.read(context).stored;
    _server = TextEditingController(text: stored?.serverUrl.toString());
    _email = TextEditingController(text: stored?.email);
  }

  @override
  void dispose() {
    for (final c in [_server, _email, _key, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openKit() async {
    final text = await (widget.readKitFile ?? _openKitFile)();
    if (text == null || !mounted) return;
    final kit = parseRecoveryKitText(text);
    setState(() {
      if (kit.server case final server?) _server.text = '$server';
      if (kit.email case final email?) _email.text = email;
      if (kit.recoveryKey case final key?) _key.text = key;
    });
  }

  static Future<String?> _openKitFile() async => (await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'TXT', extensions: ['txt']),
    ],
  ))?.readAsString();

  // A mistyped key is refused here, before any request.
  void _next() {
    final l = AppLocalizations.of(context);
    try {
      RecoveryKey.decode(_key.text);
    } on InvalidRecoveryKey catch (e) {
      return setState(() => problem = describeError(l, e));
    }
    setState(() {
      problem = null;
      _step = 2;
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final local = checkNewPassword(l, _password.text, _confirm.text);
    if (local != null) return setState(() => problem = local);
    final server = Uri.parse(_server.text.trim());
    final email = _email.text.trim();
    await run(() async {
      final key = await AppScope.read(context).recover(
        server: server,
        email: email,
        recoveryKey: _key.text,
        newPassword: _password.text,
      );
      if (mounted) {
        setState(() => _done = (key: key, server: server, email: email));
      }
    });
  }

  // Signs in on this device with the new password; a failure leaves the login screen to do it.
  Future<void> _finish(({String key, Uri server, String email}) done) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    try {
      await state.login(
        server: done.server,
        email: done.email,
        password: _password.text,
      );
      navigator.maybePop();
    } on Exception catch (e) {
      navigator.maybePop();
      // this screen is gone once popped: the navigator's context outlives it
      final host = navigator.context;
      if (host.mounted) {
        showUfToast(host, describeError(l, e), tone: UfToastTone.warn);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_done case final done?) {
      return RecoveryKitView(
        recoveryKey: done.key,
        server: done.server,
        email: done.email,
        onDone: () => _finish(done),
      );
    }
    final first = _step == 1;
    return Scaffold(
      body: LockFrame(
        step: l.stepOf(_step, 2),
        title: first ? l.recoverTitle : l.recoverPasswordTitle,
        subtitle: first ? l.recoverSubtitle : l.recoverPasswordSubtitle,
        children: first ? _identifyStep(l) : _passwordStep(l),
      ),
    );
  }

  List<Widget> _identifyStep(AppLocalizations l) => [
    keyedField(
      'recover-server',
      _server,
      l.loginServer,
      keyboard: TextInputType.url,
    ),
    keyedField(
      'recover-email',
      _email,
      l.loginEmail,
      keyboard: TextInputType.emailAddress,
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const Key('recover-open-kit'),
        onPressed: _openKit,
        child: Text(l.recoverOpenKit),
      ),
    ),
    keyedField(
      'recover-key',
      _key,
      l.recoverKey,
      mono: true,
      hint: 'XXXX-XXXX-XXXX-XXXX-\u2026',
      onSubmitted: (_) => _next(),
    ),
    if (problem case final problem?) UfErrorLine(problem),
    LockActions(
      primary: FilledButton(
        key: const Key('recover-next'),
        onPressed: _next,
        child: Text(l.stepNext),
      ),
      links: [CancelButton(onPressed: () => Navigator.of(context).maybePop())],
    ),
  ];

  List<Widget> _passwordStep(AppLocalizations l) => [
    keyedField(
      'recover-password',
      _password,
      l.recoverNewPassword,
      secret: true,
      strength: true,
    ),
    keyedField('recover-confirm', _confirm, l.setupConfirm, secret: true),
    LockNotice(l.setupWarning),
    if (problem case final problem?) UfErrorLine(problem),
    LockActions(
      primary: BusyButton(
        key: const Key('recover-submit'),
        busy: busy,
        onPressed: _submit,
        label: l.recoverSubmit,
      ),
      links: [
        TextButton(
          key: const Key('recover-back'),
          onPressed: () => setState(() {
            problem = null;
            _step = 1;
          }),
          child: Text(l.recoverBack),
        ),
      ],
    ),
  ];
}

/// The lock screens' link to [RecoveryScreen].
class RecoverLink extends StatelessWidget {
  const RecoverLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const RecoveryScreen())),
    child: Text(AppLocalizations.of(context).loginToRecover),
  );
}
