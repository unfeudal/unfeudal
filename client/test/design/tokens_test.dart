// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/tokens.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('tokens match the design palette', () {
    const light = UfColors.light, dark = UfColors.dark;
    expect(
      [
        light.bg,
        light.rail,
        light.side,
        light.panel,
        light.field,
        light.select,
        light.text,
        light.muted,
      ],
      const [
        Color(0xFFE7ECEA),
        Color(0xFFDCE3E0),
        Color(0xFFEEF2F0),
        Color(0xFFFFFFFF),
        Color(0xFFE4E9E7),
        Color(0xFFD3DEEA),
        Color(0xFF252B31),
        Color(0xFF5A646D),
      ],
    );
    expect(
      [
        light.accent,
        light.accentBg,
        light.accentFg,
        light.ok,
        light.warn,
        light.danger,
      ],
      const [
        Color(0xFF23466E),
        Color(0xFF23466E),
        Color(0xFFF4F7FA),
        Color(0xFF56664A),
        Color(0xFF8A6A1F),
        Color(0xFFA23B32),
      ],
    );
    expect(
      [
        dark.bg,
        dark.rail,
        dark.side,
        dark.panel,
        dark.field,
        dark.select,
        dark.text,
        dark.muted,
      ],
      const [
        Color(0xFF171B1F),
        Color(0xFF121518),
        Color(0xFF1B2025),
        Color(0xFF22282E),
        Color(0xFF2A3138),
        Color(0xFF26374B),
        Color(0xFFE1E7E4),
        Color(0xFF97A29D),
      ],
    );
    expect(
      [
        dark.accent,
        dark.accentBg,
        dark.accentFg,
        dark.ok,
        dark.warn,
        dark.danger,
      ],
      const [
        Color(0xFF8EB0D8),
        Color(0xFF2F5A8A),
        Color(0xFFF2F6FA),
        Color(0xFF9DB089),
        Color(0xFFC9A54E),
        Color(0xFFD9645A),
      ],
    );
  });

  test('muted text reaches 4.5:1 on window and panel', () {
    for (final c in [UfColors.light, UfColors.dark]) {
      expect(contrast(c.muted, c.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(c.muted, c.panel), greaterThanOrEqualTo(4.5));
    }
  });

  test('theme uses the bundled fonts, 8 px controls and no default shadow', () {
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
      expect(shape.borderRadius, BorderRadius.circular(8));
      expect(t.cardTheme.elevation, 0);
      expect(t.dialogTheme.shape, isA<RoundedRectangleBorder>());
    }
  });
}
