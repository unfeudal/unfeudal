// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';

Map<String, Object?> arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, Object?>;
Set<String> keys(Map<String, Object?> a) =>
    a.keys.where((k) => !k.startsWith('@')).toSet();
Set<String> holes(String s) =>
    RegExp(r'\{(\w+)').allMatches(s).map((m) => m[1]!).toSet();

void main() {
  test('EN and FR have the same keys and placeholders', () {
    final en = arb('en'), fr = arb('fr');
    expect(keys(fr), keys(en));
    for (final k in keys(en)) {
      expect(holes(fr[k]! as String), holes(en[k]! as String), reason: k);
    }
  });

  test('French copy uses neutral forms', () {
    final fr = arb('fr');
    final personal = RegExp(
      r"(^|[\s'\u2019(])(tu|vous|votre|vos|ton|ta|tes|toi)(?=[\s.,;:!?)]|$)",
      caseSensitive: false,
    );
    for (final k in keys(fr)) {
      expect(
        personal.hasMatch(fr[k]! as String),
        isFalse,
        reason: '$k: ${fr[k]}',
      );
    }
  });

  test('no hard-coded user-facing string anywhere under lib/src', () {
    final literal = RegExp(
      r'''(\bText\(\s*|\b(hintText|labelText|helperText|tooltip|semanticsLabel|title|message):\s*)['"][^'"]*[A-Za-zÀ-ÿ]''',
    );
    final offenders = <String>[];
    for (final f
        in Directory('lib/src')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('every ARB key is used by the code', () {
    final code = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.contains('app_localizations'))
          f.readAsStringSync(),
    ].join('\n');
    expect([
      for (final k in keys(arb('en')))
        if (!RegExp('\\.$k\\b').hasMatch(code)) k,
    ], isEmpty);
  });

  test('generated localisation files carry the SPDX header', () {
    for (final f in Directory(
      'lib/l10n',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(
        f.readAsLinesSync().first,
        '// SPDX-License-Identifier: Apache-2.0',
        reason: f.path,
      );
    }
  });

  test('both locales load', () async {
    expect(
      (await AppLocalizations.delegate.load(const Locale('en'))).appName,
      'Unfeudal',
    );
    expect(
      (await AppLocalizations.delegate.load(const Locale('fr'))).appName,
      'Unfeudal',
    );
  });
}
