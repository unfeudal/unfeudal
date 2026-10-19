// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/tokens.dart';
import '../lock/lock_frame.dart';
import '../save_file.dart';

/// What a recovery kit prints.
typedef RecoveryKit = ({
  Uri server,
  String email,
  DateTime created,
  String recoveryKey,
  String instructions,
});

/// The text kit. The `Server:`, `Account:`, `Created:` labels are fixed (not translated); the instructions are.
String recoveryKitText(RecoveryKit kit) {
  final (:server, :email, :created, :recoveryKey, :instructions) = kit;
  final day = created.toUtc().toIso8601String().substring(0, 10);
  return 'Server: $server\nAccount: $email\nCreated: $day\n\n$recoveryKey\n\n$instructions\n';
}

/// Reads back a text kit: the `Server:` and `Account:` lines and the key; anything missing is null.
({Uri? server, String? email, String? recoveryKey}) parseRecoveryKitText(
  String text,
) {
  final lines = [for (final line in text.split('\n')) line.trim()];
  String? labelled(String label) => lines
      .where((line) => line.startsWith('$label: '))
      .map((line) => line.substring(label.length + 2).trim())
      .firstOrNull;
  final key = RegExp(r'^[A-Z2-7]{4}(-[A-Z2-7]{4}){12}-[A-Z2-7]$');
  return (
    server: switch (labelled('Server')) {
      final url? => Uri.tryParse(url),
      null => null,
    },
    email: labelled('Account'),
    recoveryKey: lines.where(key.hasMatch).firstOrNull,
  );
}

/// One A4 page rendering the lines of [recoveryKitText] under [title]; the key in JetBrains Mono, four groups per line.
Future<Uint8List> buildRecoveryKitPdf(RecoveryKit kit, {String? title}) async {
  final recoveryKey = kit.recoveryKey;
  Future<pw.Font> font(String file) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
  final body = await font('HankenGrotesk-Regular.ttf');
  final titleFont = await font('Alegreya-Bold.ttf');
  final mono = await font('JetBrainsMono-Regular.ttf');
  final lines = recoveryKitText(kit).trimRight().split('\n');
  final groups = recoveryKey.split('-');
  final keyLines = [
    for (var i = 0; i < groups.length; i += 4)
      groups.sublist(i, (i + 4).clamp(0, groups.length)).join('-'),
  ];
  final doc = pw.Document()
    ..addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(56),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SvgImage(svg: _logoSvg, width: 48),
            pw.SizedBox(height: 16),
            if (title != null)
              pw.Text(
                title,
                style: pw.TextStyle(font: titleFont, fontSize: 22),
              ),
            pw.SizedBox(height: 8),
            for (final line in lines.take(3))
              pw.Text(line, style: pw.TextStyle(font: body, fontSize: 12)),
            pw.SizedBox(height: 24),
            for (final line in keyLines)
              pw.Text(line, style: pw.TextStyle(font: mono, fontSize: 20)),
            pw.SizedBox(height: 24),
            pw.Text(lines.last, style: pw.TextStyle(font: body, fontSize: 12)),
          ],
        ),
      ),
    );
  return doc.save();
}

// brand/logo/logo.svg
const _logoSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill-rule="evenodd" fill="#23466E" '
    'd="M20 8 H80 A4 4 0 0 1 84 12 V58 A34 34 0 0 1 16 58 V12 A4 4 0 0 1 20 8 Z M44.5 8 H55.5 V47.34 A12 12 0 1 1 44.5 47.34 Z"/></svg>';

/// Shows the recovery key once: copy (wiped from the clipboard after 60 s), save, print, then confirm.
class RecoveryKitView extends StatefulWidget {
  const RecoveryKitView({
    super.key,
    required this.recoveryKey,
    this.server,
    this.email,
    required this.onDone,
    this.savePath,
    this.writeFile,
    this.printPdf,
  });

  final String recoveryKey;

  /// Default to the stored session's.
  final Uri? server;
  final String? email;
  final VoidCallback onDone;

  /// Native "Save as" by default; a path ending in `.txt` gets the text kit, anything else the PDF.
  final Future<String?> Function(String suggestedName)? savePath;
  final Future<void> Function(String path, Uint8List bytes)? writeFile;
  final Future<void> Function(Uint8List pdf)? printPdf;

  @override
  State<RecoveryKitView> createState() => _RecoveryKitViewState();
}

class _RecoveryKitViewState extends State<RecoveryKitView> {
  final _created = DateTime.now();
  bool _confirmed = false;
  Timer? _clear;

  RecoveryKit _kit() {
    final stored = AppScope.read(context).stored;
    return (
      server: widget.server ?? stored!.serverUrl,
      email: widget.email ?? stored!.email,
      created: _created,
      recoveryKey: widget.recoveryKey,
      instructions: AppLocalizations.of(context).kitInstructions,
    );
  }

  Future<Uint8List> _pdf() {
    return buildRecoveryKitPdf(
      _kit(),
      title: AppLocalizations.of(context).kitTitle,
    );
  }

  Future<void> _save() async {
    final path = await (widget.savePath ?? _pickSaveLocation)(
      'unfeudal-recovery-kit.pdf',
    );
    if (path == null) return;
    final bytes = path.toLowerCase().endsWith('.txt')
        ? utf8.encode(recoveryKitText(_kit()))
        : await _pdf();
    await (widget.writeFile ?? writeFileBytes)(path, bytes);
  }

  Future<void> _print() async {
    final bytes = await _pdf();
    await (widget.printPdf ??
        (b) => Printing.layoutPdf(onLayout: (_) async => b))(bytes);
  }

  static Future<String?> _pickSaveLocation(String suggestedName) =>
      pickSaveLocation(
        suggestedName,
        types: const [
          XTypeGroup(label: 'PDF', extensions: ['pdf']),
          XTypeGroup(label: 'TXT', extensions: ['txt']),
        ],
      );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 60), _wipe);
  }

  /// Clears the clipboard only if it still holds the key.
  Future<void> _wipe() async {
    _clear?.cancel();
    _clear = null;
    final now = await Clipboard.getData(Clipboard.kTextPlain);
    if (now?.text == widget.recoveryKey) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  @override
  void dispose() {
    if (_clear != null) unawaited(_wipe());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = UfColors.of(context);
    return Scaffold(
      body: LockFrame(
        title: l.kitTitle,
        subtitle: l.kitBody,
        children: [
          // ponytail: solid `edge` for the read-only frame, Flutter has no dashed border; paint one if it matters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: UfRadius.control,
              border: Border.all(color: colors.edge),
            ),
            child: SelectableText(
              widget.recoveryKey,
              key: const Key('recovery-key'),
              style: monoStyle.copyWith(fontSize: 17, height: 1.7),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('recovery-copy'),
                onPressed: _copy,
                child: Text(l.kitCopy),
              ),
              OutlinedButton(
                key: const Key('recovery-save'),
                onPressed: _save,
                child: Text(l.kitSave),
              ),
              OutlinedButton(
                key: const Key('recovery-print'),
                onPressed: _print,
                child: Text(l.kitPrint),
              ),
            ],
          ),
          Text(
            l.kitInstructions,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.muted,
              fontSize: 13,
            ),
          ),
          CheckboxListTile(
            key: const Key('recovery-confirm'),
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              l.kitConfirm,
              style: theme.textTheme.bodyMedium!.copyWith(fontSize: 13.5),
            ),
          ),
          LockActions(
            primary: FilledButton(
              key: const Key('recovery-continue'),
              onPressed: _confirmed ? widget.onDone : null,
              child: Text(l.kitContinue),
            ),
          ),
        ],
      ),
    );
  }
}
