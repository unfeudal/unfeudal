// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/tokens.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';

void main() {
  test('16 moods, 5 accessories, every pose distinct', () {
    expect(LoquetMood.values, hasLength(16));
    expect(LoquetAccessory.values, hasLength(5));
    final poses = {
      for (final m in LoquetMood.values) LoquetPose.of(m).signature,
    };
    expect(poses, hasLength(16));
  });

  test('covering, peeking, alert, sleep, search and dizzy faces', () {
    expect(LoquetPose.of(LoquetMood.covering).hands, LoquetHands.cover);
    expect(LoquetPose.of(LoquetMood.peeking).hands, LoquetHands.peek);
    expect(LoquetPose.of(LoquetMood.peeking).eyes, LoquetEyes.oneOpen);
    expect(LoquetPose.of(LoquetMood.alert).extras, {LoquetExtra.sweat});
    expect(LoquetPose.of(LoquetMood.sleep).extras, {LoquetExtra.zzz});
    expect(LoquetPose.of(LoquetMood.search).extras, {LoquetExtra.magnifier});
    expect(LoquetPose.of(LoquetMood.dizzy).eyes, LoquetEyes.spiral);
    for (final m in LoquetMood.values.where(
      (m) => m != LoquetMood.covering && m != LoquetMood.peeking,
    )) {
      expect(
        LoquetPose.of(m).hands,
        LoquetHands.none,
        reason: '$m: hands only when needed',
      );
    }
  });

  test('watching eyes follow eyeX, clamped', () {
    expect(LoquetPose.of(LoquetMood.watching, eyeX: 0).lookX, -6);
    expect(LoquetPose.of(LoquetMood.watching, eyeX: 1).lookX, 6);
    expect(LoquetPose.of(LoquetMood.watching, eyeX: 4).lookX, 6);
    expect(LoquetPose.of(LoquetMood.idle, eyeX: 0).lookX, 0);
  });

  test('serious moods and body tones', () {
    expect(LoquetMood.values.where((m) => m.isSerious).toSet(), {
      LoquetMood.alert,
      LoquetMood.sad,
      LoquetMood.offline,
    });
    expect(LoquetPose.of(LoquetMood.sad).tone, LoquetTone.danger);
    expect(LoquetPose.of(LoquetMood.alert).tone, LoquetTone.danger);
    expect(LoquetPose.of(LoquetMood.offline).tone, LoquetTone.warn);
    expect(LoquetPose.of(LoquetMood.idle).tone, LoquetTone.normal);
  });

  test('palette reads the theme roles', () {
    for (final c in [UfColors.light, UfColors.dark]) {
      expect(LoquetPalette.of(LoquetTone.normal, c).body, c.accent);
      expect(LoquetPalette.of(LoquetTone.danger, c).body, c.danger);
      expect(LoquetPalette.of(LoquetTone.warn, c).body, c.warn);
      for (final tone in LoquetTone.values) {
        final p = LoquetPalette.of(tone, c);
        expect((p.face, p.feet, p.drop), (c.accentFg, c.text, c.accentText));
      }
    }
  });
}
