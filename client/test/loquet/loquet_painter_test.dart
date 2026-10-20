// SPDX-License-Identifier: Apache-2.0
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/tokens.dart';
import 'package:unfeudal_client/src/loquet/loquet_painter.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';

void main() {
  test('body: logo silhouette with the notch left open', () {
    final body = loquetBodyPath();
    expect(body.contains(const Offset(30, 30)), isTrue);
    expect(body.contains(const Offset(50, 14)), isFalse); // notch, even-odd
    // Rounded bottom (radius 34).
    expect(body.contains(const Offset(50, 90)), isTrue);
    expect(body.getBounds(), const Rect.fromLTRB(16, 8, 84, 92));
  });

  test('every mood with every accessory paints', () {
    for (final m in LoquetMood.values) {
      for (final a in [null, ...LoquetAccessory.values]) {
        final rec = PictureRecorder();
        expect(
          () => LoquetPainter(
            pose: LoquetPose.of(m),
            palette: LoquetPalette.of(LoquetPose.of(m).tone, UfColors.light),
            accessory: a,
          ).paint(Canvas(rec), const Size(96, 96)),
          returnsNormally,
          reason: '$m $a',
        );
        rec.endRecording().dispose();
      }
    }
  });

  test('repaints only on a change', () {
    LoquetPainter p({double blink = 0}) => LoquetPainter(
      pose: LoquetPose.of(LoquetMood.idle),
      palette: LoquetPalette.of(LoquetTone.normal, UfColors.light),
      blink: blink,
    );
    expect(p().shouldRepaint(p()), isFalse);
    expect(p(blink: 1).shouldRepaint(p()), isTrue);
  });
}
