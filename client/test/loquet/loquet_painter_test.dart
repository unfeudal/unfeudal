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
    expect(
      body.contains(const Offset(50, 90)),
      isTrue,
    ); // rounded bottom (r 34)
    expect(body.getBounds(), const Rect.fromLTRB(16, 8, 84, 92));
  });

  test('hats sit above the head, glasses and nose on the face', () {
    for (final a in [
      LoquetAccessory.hardHat,
      LoquetAccessory.woollyHat,
      LoquetAccessory.partyHat,
    ]) {
      expect(loquetAccessoryPath(a).getBounds().top, lessThan(8), reason: '$a');
    }
    for (final a in [LoquetAccessory.sunglasses, LoquetAccessory.fakeNose]) {
      final b = loquetAccessoryPath(a).getBounds();
      // the mockup's fake nose has eyebrows (y 27) and a moustache (y 68)
      expect(b.top, greaterThan(20), reason: '$a');
      expect(b.bottom, lessThan(70), reason: '$a');
    }
  });

  test('every mood with every accessory paints', () {
    for (final m in LoquetMood.values) {
      for (final a in [null, ...LoquetAccessory.values]) {
        final rec = PictureRecorder();
        LoquetPainter(
          pose: LoquetPose.of(m),
          palette: LoquetPalette.of(LoquetPose.of(m).tone, UfColors.light),
          accessory: a,
        ).paint(Canvas(rec), const Size(96, 96));
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
