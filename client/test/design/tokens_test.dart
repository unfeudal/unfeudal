// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/tokens.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('roles match the palette, light then dark', () {
    Map<String, Color> roles(UfColors c) => {
      'bg': c.bg,
      'side': c.side,
      'panel': c.panel,
      'field': c.field,
      'term': c.term,
      'line': c.line,
      'edge': c.edge,
      'text': c.text,
      'muted': c.muted,
      'neutral': c.neutral,
      'accent': c.accent,
      'accentFg': c.accentFg,
      'accentText': c.accentText,
      'select': c.select,
      'focus': c.focus,
      'danger': c.danger,
      'onDanger': c.onDanger,
      'dangerSoft': c.dangerSoft,
      'ok': c.ok,
      'warn': c.warn,
    };
    expect(roles(UfColors.light), const {
      'bg': Color(0xFFEDF0EE),
      'side': Color(0xFFF6F8F7),
      'panel': Color(0xFFFFFFFF),
      'field': Color(0xFFFFFFFF),
      'term': Color(0xFFFFFFFF),
      'line': Color(0xFFD8E0DB),
      'edge': Color(0xFF7B8A83),
      'text': Color(0xFF18201C),
      'muted': Color(0xFF52605A),
      'neutral': Color(0xFFE3E9E5),
      'accent': Color(0xFF2F6B57),
      'accentFg': Color(0xFFFFFFFF),
      'accentText': Color(0xFF245544),
      'select': Color(0xFFD9E8E0),
      'focus': Color(0xFF2F6B57),
      'danger': Color(0xFFB03A4E),
      'onDanger': Color(0xFFFFFFFF),
      'dangerSoft': Color(0xFFF5DFE3),
      'ok': Color(0xFF4F6526),
      'warn': Color(0xFF9A5523),
    });
    expect(roles(UfColors.dark), const {
      'bg': Color(0xFF121715),
      'side': Color(0xFF161C19),
      'panel': Color(0xFF1E2622),
      'field': Color(0xFF1B221F),
      'term': Color(0xFF0E1210),
      'line': Color(0xFF28322D),
      'edge': Color(0xFF6E8077),
      'text': Color(0xFFE3E9E5),
      'muted': Color(0xFF94A39C),
      'neutral': Color(0xFF28322D),
      'accent': Color(0xFF86AE9A),
      'accentFg': Color(0xFF0F1A15),
      'accentText': Color(0xFFA9CDBA),
      'select': Color(0xFF223229),
      'focus': Color(0xFFA9CDBA),
      'danger': Color(0xFFE57A87),
      'onDanger': Color(0xFF1A0E10),
      'dangerSoft': Color(0xFF3A2228),
      'ok': Color(0xFFB9C77A),
      'warn': Color(0xFFD08A55),
    });
  });

  test('text pairs reach 4.5:1 and edges 3:1 in both themes', () {
    for (final c in [UfColors.light, UfColors.dark]) {
      for (final (fg, bg) in [
        (c.text, c.bg),
        (c.muted, c.bg),
        (c.muted, c.panel),
        (c.accentFg, c.accent),
        (c.accentText, c.select),
        (c.onDanger, c.danger),
        (c.danger, c.dangerSoft),
        (c.warn, c.warnSoft),
      ]) {
        expect(
          contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$fg on $bg',
        );
      }
      expect(contrast(c.edge, c.bg), greaterThanOrEqualTo(3));
      expect(contrast(c.focus, c.bg), greaterThanOrEqualTo(3));
    }
  });

  test('theme uses the bundled fonts, 6 px controls and flat surfaces', () {
    for (final b in Brightness.values) {
      final t = ufTheme(b);
      expect(
        t.extension<UfColors>(),
        b == Brightness.light ? UfColors.light : UfColors.dark,
      );
      expect(t.textTheme.bodyMedium!.fontFamily, 'HankenGrotesk');
      expect(t.textTheme.headlineMedium!.fontFamily, 'Alegreya');
      expect(
        t.textTheme.bodyMedium!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      final shape =
          t.filledButtonTheme.style!.shape!.resolve({})!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, UfRadius.control);
      expect(t.filledButtonTheme.style!.minimumSize!.resolve({})!.height, 32);
      expect(t.cardTheme.elevation, 0);
      expect(
        (t.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
        UfRadius.dialog,
      );
    }
  });
}
