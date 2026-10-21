// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/motion.dart';

void main() {
  test('normal motion uses the 90/120/160/280 ms steps', () {
    const m = UfMotion.normal;
    expect(
      (m.instant, m.fast, m.base, m.slow),
      (
        const Duration(milliseconds: 90),
        const Duration(milliseconds: 120),
        const Duration(milliseconds: 160),
        const Duration(milliseconds: 280),
      ),
    );
  });

  test('the curves are standard, enter and exit', () {
    expect(UfMotion.standard, const Cubic(0.2, 0, 0, 1));
    expect(UfMotion.enter, const Cubic(0.05, 0.7, 0.1, 1));
    expect(UfMotion.exit, const Cubic(0.3, 0, 1, 1));
  });

  test('still motion has no duration', () {
    expect([
      UfMotion.still.instant,
      UfMotion.still.fast,
      UfMotion.still.base,
      UfMotion.still.slow,
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
