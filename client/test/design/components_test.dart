// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/design/banner.dart';
import 'package:unfeudal_client/src/design/empty_state.dart';
import 'package:unfeudal_client/src/design/logo.dart';
import 'package:unfeudal_client/src/design/motion.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/design/tokens.dart';

Widget host(Widget child, {bool still = false}) => MaterialApp(
  theme: ufTheme(Brightness.light),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MotionScope(
    performanceMode: still,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('every seal state has its own label', (t) async {
    final labels = <String>{};
    for (final s in SealState.values) {
      await t.pumpWidget(host(Seal(state: s), still: true));
      labels.add(t.getSemantics(find.byType(Seal)).label);
    }
    expect(labels, hasLength(SealState.values.length));
  });

  testWidgets('connecting spins, still mode is static', (t) async {
    await t.pumpWidget(host(const Seal(state: SealState.connecting)));
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpWidget(
      host(const Seal(state: SealState.connecting), still: true),
    );
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('empty state: title, one line, at most two actions', (t) async {
    await t.pumpWidget(
      host(
        EmptyState(
          title: 'T',
          body: 'B',
          primary: ('Go', () {}),
          secondary: ('Later', () {}),
        ),
      ),
    );
    expect(find.text('T'), findsOneWidget);
    expect(find.byType(UfLogo), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('banner tones use the token colours and keep one action', (
    t,
  ) async {
    var tapped = 0;
    await t.pumpWidget(
      host(
        StatusBanner(
          tone: BannerTone.danger,
          message: 'M',
          action: ('Retry', () => tapped++),
        ),
      ),
    );
    final box = t.widget<Material>(
      find
          .descendant(
            of: find.byType(StatusBanner),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(box.color, UfColors.light.dangerSoft);
    await t.tap(find.text('Retry'));
    expect(tapped, 1);
  });
}
