// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/tokens.dart';
import 'package:unfeudal_client/src/loquet/loquet.dart';
import 'package:unfeudal_client/src/loquet/loquet_painter.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';

Widget host(Widget child) => MaterialApp(
  theme: ufTheme(Brightness.light),
  home: Center(child: child),
);

LoquetPainter painterOf(WidgetTester t) =>
    t
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(Loquet),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as LoquetPainter;

void main() {
  testWidgets('still: a mood change is instant and nothing animates', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const Loquet(
          mood: LoquetMood.idle,
          still: true,
          semanticLabel: 'Loquet',
        ),
      ),
    );
    await t.pumpWidget(
      host(
        const Loquet(
          mood: LoquetMood.happy,
          still: true,
          semanticLabel: 'Loquet',
        ),
      ),
    );
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    expect(painterOf(t).pose.mood, LoquetMood.happy);
  });

  testWidgets(
    'moving: cross-fades, then the entry effect ends and the tree settles',
    (t) async {
      await t.pumpWidget(
        host(const Loquet(mood: LoquetMood.idle, semanticLabel: 'Loquet')),
      );
      await t.pumpWidget(
        host(const Loquet(mood: LoquetMood.happy, semanticLabel: 'Loquet')),
      );
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
      expect(painterOf(t).pose.mood, LoquetMood.happy);
    },
  );

  testWidgets('idle life runs only with life on, and stops on dispose', (
    t,
  ) async {
    await t.pumpWidget(
      host(const Loquet(mood: LoquetMood.idle, semanticLabel: 'Loquet')),
    );
    await t.pump(const Duration(seconds: 10));
    expect(t.hasRunningAnimations, isFalse);
    await t.pumpWidget(
      host(
        const Loquet(
          mood: LoquetMood.idle,
          life: true,
          semanticLabel: 'Loquet',
        ),
      ),
    );
    await t.pump(const Duration(seconds: 5));
    expect(painterOf(t).blink > 0 || t.hasRunningAnimations, isTrue);
    await t.pumpWidget(host(const SizedBox()));
    await t.pump(const Duration(seconds: 10)); // no pending timer left
  });

  testWidgets('life is ignored when still', (t) async {
    await t.pumpWidget(
      host(
        const Loquet(
          mood: LoquetMood.idle,
          life: true,
          still: true,
          semanticLabel: 'Loquet',
        ),
      ),
    );
    await t.pump(const Duration(seconds: 10));
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('size, accessory and accessible label', (t) async {
    await t.pumpWidget(
      host(
        const Loquet(
          mood: LoquetMood.idle,
          size: 56,
          accessory: LoquetAccessory.partyHat,
          semanticLabel: 'Loquet, resting',
        ),
      ),
    );
    expect(t.getSize(find.byType(Loquet)), const Size(56, 56));
    expect(painterOf(t).accessory, LoquetAccessory.partyHat);
    expect(find.bySemanticsLabel('Loquet, resting'), findsOneWidget);
  });
}
