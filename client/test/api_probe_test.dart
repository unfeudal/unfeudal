// SPDX-License-Identifier: Apache-2.0

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqlite3/sqlite3.dart' hide Version;
import 'package:unfeudal_client/src/version.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('version constants', () {
    expect(Version.parse(clientVersion).toString(), clientVersion);
    expect(clientApis, [1]);
    expect(Uri.parse(officialReleasesUrl).scheme, 'https');
  });

  test('dartssh2 handler shapes', () {
    expect([
      <SSHHostkeyVerifyHandler>[(String type, Uint8List fingerprint) => false],
      <SSHPasswordRequestHandler>[() => 'pw'],
      <SSHUserInfoRequestHandler>[
        (SSHUserInfoRequest r) => [
          for (final p in r.prompts) p.echo ? p.promptText : '',
        ],
      ],
    ], hasLength(3));
    expect(const SSHPtyConfig(width: 80, height: 24).width, 80);
    expect(SSHAuthFailError('denied'), isA<SSHAuthError>());
  });

  test(
    'dartssh2 reads back an ed25519 key it wrote with a passphrase',
    () async {
      final kp = await Ed25519().newKeyPair();
      final seed = await kp.extractPrivateKeyBytes();
      final pub = (await kp.extractPublicKey()).bytes;
      final pair = OpenSSHEd25519KeyPair(
        Uint8List.fromList(pub),
        Uint8List.fromList([...seed, ...pub]),
        'probe',
      );
      final back = SSHKeyPair.fromPem(
        pair.toPem(passphrase: 'pw'),
        'pw',
      ).single;
      expect(back.type, 'ssh-ed25519');
      expect(back.toPublicKey().encode(), pair.toPublicKey().encode());
    },
  );

  test('xterm2 terminal surface', () {
    final t = Terminal(maxLines: 1000);
    String? sent;
    t.onOutput = (data) => sent = data;
    t.write('hello');
    expect(t.buffer.getText(), contains('hello'));
    t.textInput('a');
    expect(sent, 'a');
    expect(TerminalView(t), isA<Widget>());
  });

  test('sqlite3, secure storage and pdf entry points', () async {
    final db = sqlite3.openInMemory();
    expect(db.select('PRAGMA user_version').single.values.single, 0);
    db.close();
    expect(
      const FlutterSecureStorage(
        mOptions: MacOsOptions(usesDataProtectionKeychain: false),
      ),
      isNotNull,
    );
    final doc = pw.Document()
      ..addPage(
        pw.Page(pageFormat: PdfPageFormat.a4, build: (_) => pw.SizedBox()),
      );
    expect(String.fromCharCodes((await doc.save()).take(5)), '%PDF-');
  });

  test('Argon2id at the floor fits the unlock budget', () async {
    final sw = Stopwatch()..start();
    await deriveMasterKeys('probe-password', Uint8List(16), KdfParams.defaults);
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  }, tags: 'slow');

  test(
    'dartssh2: a forwarded channel is an SSHSocket another client can run over',
    () {
      Future<SSHSocket> forward(SSHClient c) =>
          c.forwardLocal('target.lan', 22);
      SSHClient over(SSHSocket channel) => SSHClient(
        channel,
        username: 'u',
        onVerifyHostKey: (type, fp) => false,
      );
      expect([forward, over], hasLength(2));
    },
  );

  test('xterm2: paste follows the remote bracketed-paste mode', () {
    final term = Terminal();
    final out = <String>[];
    term.onOutput = out.add;
    expect(term.bracketedPasteMode, isFalse);
    term.paste('a\nb');
    term.write('\x1b[?2004h');
    expect(term.bracketedPasteMode, isTrue);
    term.paste('c');
    expect(out, [
      'a\rb',
      '\x1b[200~c\x1b[201~',
    ]); // paste sends a line break as \r
  });

  test('xterm2: selection, highlights and buffer text', () {
    final term = Terminal()..write('hello world\r\nsecond');
    final c = TerminalController();
    c.setSelection(
      term.buffer.createAnchor(0, 0),
      term.buffer.createAnchor(5, 0),
    );
    expect(term.buffer.getText(c.selection), 'hello');
    final h = c.highlight(
      p1: term.buffer.createAnchor(6, 0),
      p2: term.buffer.createAnchor(11, 0),
      color: Colors.yellow,
    );
    expect(c.highlights, hasLength(1));
    h.dispose();
    c.clearSelection();
    expect(c.selection, isNull);
    expect(c.highlights, isEmpty);
    expect(term.buffer.lines[1].getText(), startsWith('second'));
  });

  testWidgets(
    'xterm2: onKeyEvent runs before the terminal; empty shortcuts drop the built-in copy',
    (t) async {
      final term = Terminal();
      final sent = <String>[];
      term.onOutput = sent.add;
      final seen = <LogicalKeyboardKey>[];
      await t.pumpWidget(
        MaterialApp(
          home: TerminalView(
            term,
            controller: TerminalController(),
            scrollController: ScrollController(),
            autofocus: true,
            shortcuts: const {},
            textStyle: const TerminalStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
            ),
            onSecondaryTapDown: (details, offset) {},
            onKeyEvent: (node, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.keyF &&
                  HardwareKeyboard.instance.isShiftPressed) {
                seen.add(e.logicalKey);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
          ),
        ),
      );
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyF);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(seen, [LogicalKeyboardKey.keyF]);
      expect(sent, isEmpty);
      await t.sendKeyEvent(LogicalKeyboardKey.keyC);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(sent, ['\x03']);
    },
  );
}
