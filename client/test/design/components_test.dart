// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/design/banner.dart';
import 'package:unfeudal_client/src/design/choices.dart';
import 'package:unfeudal_client/src/design/dialog.dart';
import 'package:unfeudal_client/src/design/empty_state.dart';
import 'package:unfeudal_client/src/design/logo.dart';
import 'package:unfeudal_client/src/design/motion.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/design/segmented.dart';
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
  testWidgets(
    'segmented: the pill slides from the old segment to the picked one',
    (t) async {
      var picked = 0;
      Widget control() => host(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: UfSegmented<int>(
              segments: [
                for (final i in [0, 1, 2]) (i, Text('S$i')),
              ],
              selected: picked,
              onChanged: (v) => setState(() => picked = v),
            ),
          ),
        ),
      );
      await t.pumpWidget(control());
      // the pill is the track's first child: the only bare DecoratedBox
      double pillX() => t
          .getTopLeft(
            find
                .descendant(
                  of: find.byType(UfSegmented<int>),
                  matching: find.byType(DecoratedBox),
                )
                .at(1),
          )
          .dx;
      final start = pillX();
      final end = t.getTopLeft(find.text('S2')).dx;
      await t.tap(find.text('S2'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(pillX(), allOf(greaterThan(start), lessThan(end)));
      await t.pumpAndSettle();
      expect(picked, 2);
      expect(pillX(), lessThan(end));
      expect(t.getRect(find.text('S2')).left - pillX(), closeTo(12, 0.5));
    },
  );

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

  testWidgets('empty state: title, one line, one action', (t) async {
    await t.pumpWidget(
      host(EmptyState(title: 'T', body: 'B', primary: ('Go', () {}))),
    );
    expect(find.text('T'), findsOneWidget);
    expect(find.byType(UfLogo), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
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

  testWidgets('switch: a tap toggles it and the thumb slides across', (
    t,
  ) async {
    var on = false;
    await t.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: UfSwitch(
              value: on,
              onChanged: (v) => setState(() => on = v),
            ),
          ),
        ),
      ),
    );
    final thumb = find.descendant(
      of: find.byType(AnimatedAlign),
      matching: find.byType(Container),
    );
    final start = t.getTopLeft(thumb).dx;
    await t.tap(find.byType(UfSwitch));
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    expect(on, isTrue);
    expect(
      t.getTopLeft(thumb).dx,
      allOf(greaterThan(start), lessThan(start + 14)),
    );
    await t.pumpAndSettle();
    expect(t.getTopLeft(thumb).dx, closeTo(start + 14, 0.5));
  });

  testWidgets('switch: a disabled one reads as disabled and off', (t) async {
    await t.pumpWidget(
      host(const Center(child: UfSwitch(value: false, onChanged: null))),
    );
    expect(
      t.getSemantics(find.byType(UfSwitch)),
      isSemantics(isToggled: false, isEnabled: false),
    );
  });

  testWidgets('select: opens a menu as wide as itself and picks an option', (
    t,
  ) async {
    String? picked;
    await t.pumpWidget(
      host(
        Center(
          child: SizedBox(
            width: 240,
            child: UfSelect<String?>(
              key: const Key('pick'),
              options: const [
                UfOption('a', 'Alpha', key: Key('opt-a')),
                UfOption('b', 'Bravo', key: Key('opt-b')),
                UfOption('c', 'Charlie', key: Key('opt-c'), enabled: false),
              ],
              value: picked,
              onChanged: (v) => picked = v,
            ),
          ),
        ),
      ),
    );
    expect(t.getSize(find.byKey(const Key('pick'))).height, 32);
    await t.tap(find.byKey(const Key('pick')));
    await t.pumpAndSettle();
    // the menu's 4 px padding on each side
    expect(t.getSize(find.byKey(const Key('opt-a'))).width, closeTo(232, 0.5));
    expect(
      t.widget<MenuItemButton>(find.byKey(const Key('opt-c'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const Key('opt-b')));
    await t.pumpAndSettle();
    expect(picked, 'b');
    expect(find.byKey(const Key('opt-a')), findsNothing);
  });

  testWidgets('select: a disabled one stays closed', (t) async {
    await t.pumpWidget(
      host(
        const Center(
          child: SizedBox(
            width: 200,
            child: UfSelect<int>(
              options: [UfOption(1, 'One', key: Key('opt-1'))],
              value: 1,
              onChanged: null,
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(UfSelect<int>), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('opt-1')), findsNothing);
  });

  testWidgets('radio and choice card: a tap picks their value', (t) async {
    var group = 0;
    await t.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              UfRadio<int>(
                value: 1,
                groupValue: group,
                label: 'One',
                onChanged: (v) => setState(() => group = v),
              ),
              UfChoiceCard<int>(
                value: 2,
                groupValue: group,
                title: 'Two',
                onChanged: (v) => setState(() => group = v),
              ),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.text('One'));
    expect(group, 1);
    await t.tap(find.text('Two'));
    await t.pump();
    expect(group, 2);
    expect(
      t.getSemantics(find.byType(UfChoiceCard<int>)),
      isSemantics(
        label: 'Two',
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
  });

  testWidgets('checkbox row: a tap on the label toggles it', (t) async {
    var checked = false;
    await t.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => UfCheckboxRow(
            value: checked,
            label: 'Start with the session',
            onChanged: (v) => setState(() => checked = v),
          ),
        ),
      ),
    );
    await t.tap(find.text('Start with the session'));
    await t.pump();
    expect(checked, isTrue);
    expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    expect(checked, isFalse, reason: 'the box toggles once too');
  });

  testWidgets('a text field is 32 px tall, with or without an icon', (t) async {
    await t.pumpWidget(
      host(
        const Column(
          children: [
            TextField(key: Key('bare')),
            TextField(
              key: Key('icon'),
              decoration: InputDecoration(
                suffixIcon: Icon(Icons.lock, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
    expect(t.getSize(find.byKey(const Key('bare'))).height, closeTo(32, 1));
    expect(t.getSize(find.byKey(const Key('icon'))).height, closeTo(32, 1));
  });

  testWidgets('confirm danger: Escape or the scrim answers no', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      host(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
        still: true,
      ),
    );
    var answer = confirmDanger(ctx, question: 'Trash it?', action: 'Trash');
    await t.pumpAndSettle();
    expect(find.text('Trash it?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(await answer, isFalse);
    answer = confirmDanger(ctx, question: 'Trash it?', action: 'Trash');
    await t.pumpAndSettle();
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testWidgets(
    'select: Tab, Enter, then the arrows and Enter pick by keyboard',
    (t) async {
      int? picked;
      await t.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 200,
              child: UfSelect<int?>(
                options: const [
                  UfOption(1, 'One', key: Key('opt-1')),
                  UfOption(2, 'Two', key: Key('opt-2')),
                ],
                value: null,
                onChanged: (v) => picked = v,
              ),
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('opt-1')), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(picked, 2);
    },
  );
}
