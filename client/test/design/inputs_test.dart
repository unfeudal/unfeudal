// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/design/acl_grid.dart';
import 'package:unfeudal_client/src/design/feedback.dart';
import 'package:unfeudal_client/src/design/inputs.dart';
import 'package:unfeudal_client/src/design/motion.dart';
import 'package:unfeudal_client/src/design/palette.dart';
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
  group('number field', () {
    Future<int? Function()> pumpStepper(WidgetTester t, int? start) async {
      int? value = start;
      await t.pumpWidget(
        host(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) => UfNumberField(
                value: value,
                min: 1,
                max: 3,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      return () => value;
    }

    testWidgets('the arrow keys step the value and stop at the bounds', (
      t,
    ) async {
      final value = await pumpStepper(t, 2);
      await t.tap(find.byType(TextField));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(value(), 3);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(value(), 3);
      // three presses within one frame add up
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(value(), 1);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('an emptied field reports null; a step starts at the bounds', (
      t,
    ) async {
      final value = await pumpStepper(t, 2);
      await t.enterText(find.byType(TextField), '');
      await t.pump();
      expect(value(), isNull);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(value(), 2);
    });

    testWidgets('the wheel steps a focused value only; the chevrons too', (
      t,
    ) async {
      final value = await pumpStepper(t, 2);
      final idle = TestPointer(2, PointerDeviceKind.mouse)
        ..hover(t.getCenter(find.byType(TextField)));
      await t.sendEventToBinding(idle.scroll(const Offset(0, 20)));
      await t.pump();
      expect(value(), 2);
      await t.tap(find.byType(TextField));
      await t.pump();
      final mouse = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(t.getCenter(find.byType(TextField)));
      await t.sendEventToBinding(mouse.scroll(const Offset(0, 20)));
      await t.pump();
      expect(value(), 1);
      await t.tap(find.byTooltip('Increase'));
      await t.pump();
      expect(value(), 2);
    });
  });

  group('combobox', () {
    const options = [
      UfComboOption('eu', 'Europe', detail: 'eu-west'),
      UfComboOption('us', 'United States', disabledReason: 'Not allowed'),
      UfComboOption('as', 'Asia'),
      UfComboOption('au', 'Australia'),
    ];

    Future<List<String>> pumpCombo(WidgetTester t) async {
      final picked = <String>[];
      await t.pumpWidget(
        host(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 300,
              child: UfCombobox<String>(
                options: options,
                onSelected: picked.add,
              ),
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('typing filters and bolds the match', (t) async {
      await pumpCombo(t);
      await t.enterText(find.byType(TextField), 'as');
      await t.pumpAndSettle();
      expect(find.byType(UfMatchText), findsNWidgets(1));
      final match = t.widget<Text>(
        find.descendant(
          of: find.byType(UfMatchText),
          matching: find.byType(Text),
        ),
      );
      final spans = (match.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.text, 'As');
      expect(spans.first.style!.fontWeight, FontWeight.w600);
      expect(spans.last.text, 'ia');
    });

    testWidgets('a disabled option shows its reason and cannot be picked', (
      t,
    ) async {
      final picked = await pumpCombo(t);
      await t.enterText(find.byType(TextField), 'united');
      await t.pumpAndSettle();
      expect(find.text('Not allowed'), findsOneWidget);
      await t.tap(find.text('Not allowed'));
      await t.pumpAndSettle();
      expect(picked, isEmpty);
    });

    testWidgets('no match shows the empty state with the query', (t) async {
      await pumpCombo(t);
      await t.enterText(find.byType(TextField), 'zz');
      await t.pumpAndSettle();
      expect(find.text('Nothing matches “zz”.'), findsOneWidget);
    });

    testWidgets(
      'the arrows skip disabled options, Enter picks, Escape closes',
      (t) async {
        final picked = await pumpCombo(t);
        await t.tap(find.byType(TextField));
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // opens on Europe
        await t.sendKeyEvent(
          LogicalKeyboardKey.arrowDown,
        ); // skips United States
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(picked, ['as']);
        expect(find.text('Australia'), findsNothing);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
        expect(find.text('Australia'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Australia'), findsNothing);
      },
    );
  });

  testWidgets('slider: a drag changes the value and shows the tip meanwhile', (
    t,
  ) async {
    var value = 0.0;
    await t.pumpWidget(
      host(
        Center(
          child: SizedBox(
            width: 214,
            child: StatefulBuilder(
              builder: (context, setState) => UfSlider(
                value: value,
                max: 100,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('slider-tip')), findsNothing);
    final start = t.getTopLeft(find.byType(UfSlider)) + const Offset(7, 10);
    final drag = await t.startGesture(start);
    await drag.moveBy(const Offset(50, 0));
    await drag.moveBy(const Offset(50, 0));
    await t.pump();
    expect(value, closeTo(50, 1));
    expect(find.byKey(const Key('slider-tip')), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    await drag.up();
    await t.pump();
    expect(find.byKey(const Key('slider-tip')), findsNothing);
  });

  testWidgets('tri-state: allow, deny, unset, then allow again', (t) async {
    var state = UfTriState.allow;
    await t.pumpWidget(
      host(
        Center(
          child: StatefulBuilder(
            builder: (context, setState) => UfTriToggle(
              state: state,
              onChanged: (v) => setState(() => state = v),
            ),
          ),
        ),
      ),
    );
    final seen = <UfTriState>[];
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byType(UfTriToggle));
      await t.pump();
      seen.add(state);
    }
    expect(seen, [UfTriState.deny, UfTriState.unset, UfTriState.allow]);
  });

  group('shake', () {
    Widget shaking(int shakes, {bool still = false}) => host(
      Center(
        child: UfShake(shakes: shakes, child: const Text('field')),
      ),
      still: still,
    );
    double x(WidgetTester t) => t.getTopLeft(find.text('field')).dx;

    testWidgets('runs once, then rests where it started', (t) async {
      await t.pumpWidget(shaking(0));
      final rest = x(t);
      await t.pumpWidget(shaking(1));
      await t.pump(const Duration(milliseconds: 72));
      expect(x(t), closeTo(rest - 8, 0.5));
      await t.pump(const Duration(milliseconds: 300));
      expect(x(t), rest);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('does not move under performance mode', (t) async {
      await t.pumpWidget(shaking(0, still: true));
      final rest = x(t);
      await t.pumpWidget(shaking(1, still: true));
      await t.pump(const Duration(milliseconds: 72));
      expect(x(t), rest);
    });
  });

  testWidgets('stagger: only the first 8 rows animate in', (t) async {
    await t.pumpWidget(
      host(
        UfStagger(
          child: Column(
            children: [
              for (var i = 0; i < 10; i++)
                UfStaggerItem(index: i, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 10));
    double opacity(int i) => t
        .widget<Opacity>(
          find
              .ancestor(of: find.text('row $i'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(opacity(0), greaterThan(0));
    expect(opacity(0), lessThan(1));
    expect(opacity(7), 0);
    for (final i in [8, 9]) {
      expect(
        find.ancestor(
          of: find.text('row $i'),
          matching: find.byType(UfStaggerItem),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(UfStaggerItem).at(i),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    }
    await t.pumpAndSettle();
    expect(opacity(7), 1);
  });

  group('search field', () {
    testWidgets('the shortcut chip hides once typing starts', (t) async {
      await t.pumpWidget(host(const UfSearchField(shortcut: 'Ctrl K')));
      expect(find.text('Ctrl K'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'prod');
      await t.pump();
      expect(find.text('Ctrl K'), findsNothing);
      expect(find.text('Esc'), findsOneWidget);
    });

    testWidgets('Escape clears the text, then leaves the field', (t) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        host(UfSearchField(controller: controller, shortcut: 'Ctrl K')),
      );
      await t.enterText(find.byType(TextField), 'prod');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(controller.text, isEmpty);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(find.text('Ctrl K'), findsOneWidget);
    });
  });

  testWidgets('strength meter: fills as many segments as the score', (t) async {
    await t.pumpWidget(host(const UfStrengthMeter(score: 3, capsLock: false)));
    final colors = UfColors.light;
    Color segment(int i) =>
        (t.widget<Container>(find.byKey(Key('strength-$i'))).decoration!
                as BoxDecoration)
            .color!;
    expect(
      [for (var i = 0; i < 4; i++) segment(i)],
      [colors.ok, colors.ok, colors.ok, colors.line],
    );
    expect(find.text('Good. Caps Lock off.'), findsOneWidget);
  });

  testWidgets('skeleton: static when motion is still', (t) async {
    await t.pumpWidget(host(const UfTreeSkeleton(), still: true));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);
    final opacity = t.widget<Opacity>(
      find.descendant(
        of: find.byType(UfSkeleton),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('palette: lays out inside a scroll view', (t) async {
    await t.pumpWidget(
      host(
        SingleChildScrollView(
          child: UfCommandPalette(
            groups: [
              UfPaletteGroup('Actions', [
                UfPaletteRow(label: 'New host', onSelected: () {}),
              ]),
            ],
            onQueryChanged: (_) {},
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('New host'), findsOneWidget);
  });

  testWidgets('palette: the arrows move the active row and Enter runs it', (
    t,
  ) async {
    final ran = <String>[];
    UfPaletteRow row(String label) =>
        UfPaletteRow(label: label, onSelected: () => ran.add(label));
    await t.pumpWidget(
      host(
        UfCommandPalette(
          groups: [
            UfPaletteGroup('Hosts', [row('prod-web-1'), row('prod-db-1')]),
            UfPaletteGroup('Actions', [row('New host')]),
          ],
          onQueryChanged: (_) {},
          onDismiss: () => ran.add('dismissed'),
        ),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(ran, ['New host', 'dismissed']);
  });
}
