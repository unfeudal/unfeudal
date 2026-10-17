// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/motion.dart';

void main() {
  test('tokens', () {
    const m = UfMotion.normal;
    expect(
      (m.fast, m.base, m.slow, m.shake),
      (
        const Duration(milliseconds: 160),
        const Duration(milliseconds: 240),
        const Duration(milliseconds: 420),
        const Duration(milliseconds: 360),
      ),
    );
    expect(UfMotion.curve, const Cubic(0.2, 0.8, 0.2, 1));
    expect([
      UfMotion.still.fast,
      UfMotion.still.base,
      UfMotion.still.slow,
      UfMotion.still.shake,
    ], everyElement(Duration.zero));
  });

  testWidgets('performance mode or OS reduce-motion gives still motion', (
    t,
  ) async {
    late UfMotion seen;
    Widget probe({required bool performance, required bool osReduce}) =>
        MediaQuery(
          data: MediaQueryData(disableAnimations: osReduce),
          child: MotionScope(
            performanceMode: performance,
            child: Builder(
              builder: (c) {
                seen = UfMotion.of(c);
                return const SizedBox();
              },
            ),
          ),
        );
    await t.pumpWidget(probe(performance: false, osReduce: false));
    expect(seen, UfMotion.normal);
    await t.pumpWidget(probe(performance: true, osReduce: false));
    expect(seen, UfMotion.still);
    await t.pumpWidget(probe(performance: false, osReduce: true));
    expect(seen, UfMotion.still);
  });

  testWidgets('ShakeOnError shakes once per trigger change, not when still', (
    t,
  ) async {
    Widget shake(int trigger, {bool still = false}) => MaterialApp(
      home: MotionScope(
        performanceMode: still,
        child: ShakeOnError(
          trigger: trigger,
          child: const SizedBox(key: Key('x')),
        ),
      ),
    );
    await t.pumpWidget(shake(0));
    await t.pumpWidget(shake(1));
    await t.pump(const Duration(milliseconds: 90));
    expect(t.getTopLeft(find.byKey(const Key('x'))).dx, isNot(0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const Key('x'))).dx, 0);
    await t.pumpWidget(shake(2, still: true));
    await t.pump(const Duration(milliseconds: 90));
    expect(t.getTopLeft(find.byKey(const Key('x'))).dx, 0);
  });

  testWidgets('showUfDialog returns the popped value', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: MotionScope(
          performanceMode: false,
          child: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    final result = showUfDialog<int>(
      ctx,
      (c) => TextButton(
        onPressed: () => Navigator.pop(c, 7),
        child: const Text('ok'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('ok'));
    await t.pumpAndSettle();
    expect(await result, 7);
  });
}
