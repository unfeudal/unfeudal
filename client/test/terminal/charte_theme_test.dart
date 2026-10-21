// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/tokens.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/terminal/charte_theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('terminalThemeFor picks Charte by brightness, the others ignore it', () {
    expect(
      terminalThemeFor(TerminalThemeId.charte, Brightness.dark),
      same(charteDark),
    );
    expect(
      terminalThemeFor(TerminalThemeId.charte, Brightness.light),
      same(charteLight),
    );
    expect(
      terminalThemeFor(TerminalThemeId.dracula, Brightness.light),
      same(dracula),
    );
  });

  test('Charte ANSI colours reach 4.5:1 on its background', () {
    expect(
      (charteDark.background, charteLight.background),
      (UfColors.dark.term, UfColors.light.term),
    );
    for (final t in [charteDark, charteLight]) {
      for (final c in [
        t.foreground,
        t.red,
        t.green,
        t.yellow,
        t.blue,
        t.magenta,
        t.cyan,
      ]) {
        expect(
          contrast(c, t.background),
          greaterThanOrEqualTo(4.5),
          reason: '$c',
        );
      }
    }
  });
}
