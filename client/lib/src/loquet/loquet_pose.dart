// SPDX-License-Identifier: Apache-2.0
import 'dart:ui';

import '../design/tokens.dart';

enum LoquetMood {
  idle,
  watching,
  covering,
  peeking,
  happy,
  sad,
  alert,
  connecting,
  search,
  offline,
  sleep,
  sleepy,
  yawn,
  cheerful,
  concerned,
  dizzy;

  /// Never with an accessory or a joke line.
  bool get serious => this == alert || this == sad || this == offline;
}

enum LoquetAccessory { hardHat, woollyHat, partyHat, sunglasses, fakeNose }

enum LoquetEyes {
  open,
  follow,
  closed,
  oneOpen,
  arcs,
  worried,
  wide,
  up,
  aside,
  flat,
  sleepy,
  squeezed,
  cheerful,
  glance,
  spiral,
}

enum LoquetMouth {
  smile,
  smallO,
  flat,
  openSmile,
  frown,
  bigO,
  yawn,
  grin,
  wavy,
  tiny,
  zigzag,
}

enum LoquetHands { none, cover, peek }

enum LoquetExtra { sweat, zzz, magnifier, tear }

enum LoquetTone { normal, danger, warn }

/// What the painter draws for a mood: face parts, body tone and where the eyes look.
class LoquetPose {
  const LoquetPose(
    this.eyes,
    this.mouth, {
    this.hands = LoquetHands.none,
    this.extras = const {},
    this.tone = LoquetTone.normal,
    this.lookX = 0,
  });

  /// [eyeX] (0 left … 1 right) only moves the eyes of [LoquetMood.watching].
  factory LoquetPose.of(LoquetMood mood, {double eyeX = 0.5}) => switch (mood) {
    LoquetMood.idle => const LoquetPose(LoquetEyes.open, LoquetMouth.smile),
    LoquetMood.watching => LoquetPose(
      LoquetEyes.follow,
      LoquetMouth.smallO,
      lookX: eyeX.clamp(0, 1) * 12 - 6,
    ),
    LoquetMood.covering => const LoquetPose(
      LoquetEyes.closed,
      LoquetMouth.flat,
      hands: LoquetHands.cover,
    ),
    LoquetMood.peeking => const LoquetPose(
      LoquetEyes.oneOpen,
      LoquetMouth.flat,
      hands: LoquetHands.peek,
    ),
    LoquetMood.happy => const LoquetPose(
      LoquetEyes.arcs,
      LoquetMouth.openSmile,
    ),
    LoquetMood.sad => const LoquetPose(
      LoquetEyes.worried,
      LoquetMouth.frown,
      tone: LoquetTone.danger,
    ),
    LoquetMood.alert => const LoquetPose(
      LoquetEyes.wide,
      LoquetMouth.bigO,
      extras: {LoquetExtra.sweat},
      tone: LoquetTone.danger,
    ),
    LoquetMood.connecting => const LoquetPose(
      LoquetEyes.up,
      LoquetMouth.smallO,
    ),
    LoquetMood.search => const LoquetPose(
      LoquetEyes.aside,
      LoquetMouth.smallO,
      extras: {LoquetExtra.magnifier},
    ),
    LoquetMood.offline => const LoquetPose(
      LoquetEyes.flat,
      LoquetMouth.frown,
      tone: LoquetTone.warn,
    ),
    LoquetMood.sleep => const LoquetPose(
      LoquetEyes.closed,
      LoquetMouth.flat,
      extras: {LoquetExtra.zzz},
    ),
    LoquetMood.sleepy => const LoquetPose(LoquetEyes.sleepy, LoquetMouth.tiny),
    LoquetMood.yawn => const LoquetPose(
      LoquetEyes.squeezed,
      LoquetMouth.yawn,
      extras: {LoquetExtra.tear},
    ),
    LoquetMood.cheerful => const LoquetPose(
      LoquetEyes.cheerful,
      LoquetMouth.grin,
    ),
    LoquetMood.concerned => const LoquetPose(
      LoquetEyes.glance,
      LoquetMouth.wavy,
    ),
    LoquetMood.dizzy => const LoquetPose(LoquetEyes.spiral, LoquetMouth.zigzag),
  };

  final LoquetEyes eyes;
  final LoquetMouth mouth;
  final LoquetHands hands;
  final Set<LoquetExtra> extras;
  final LoquetTone tone;

  /// Horizontal eye offset in viewBox units (−6 … 6).
  final double lookX;

  /// The same pose looking [lookX] units aside (idle life).
  LoquetPose lookingAt(double lookX) => LoquetPose(
    eyes,
    mouth,
    hands: hands,
    extras: extras,
    tone: tone,
    lookX: lookX,
  );

  /// The drawn parts, without the eye offset.
  ({
    LoquetEyes eyes,
    LoquetMouth mouth,
    LoquetHands hands,
    String extras,
    LoquetTone tone,
  })
  get signature => (
    eyes: eyes,
    mouth: mouth,
    hands: hands,
    extras: (extras.map((e) => e.name).toList()..sort()).join(','),
    tone: tone,
  );

  @override
  bool operator ==(Object other) =>
      other is LoquetPose &&
      other.signature == signature &&
      other.lookX == lookX;

  @override
  int get hashCode => Object.hash(signature, lookX);
}

/// Loquet's colours, from the theme's roles: `accent` body (`danger` sad or alert, `warn` offline), an
/// `accentFg` face, `text` feet, `accentText` drops.
class LoquetPalette {
  const LoquetPalette({
    required this.body,
    required this.face,
    required this.feet,
    required this.zzz,
    required this.accent,
    required this.drop,
  });

  factory LoquetPalette.of(LoquetTone tone, UfColors c) {
    final body = switch (tone) {
      LoquetTone.normal => c.accent,
      LoquetTone.danger => c.danger,
      LoquetTone.warn => c.warn,
    };
    return LoquetPalette(
      body: body,
      face: c.accentFg,
      feet: c.text,
      zzz: c.muted,
      accent: c.accent,
      drop: c.accentText,
    );
  }

  final Color body, face, feet, zzz, accent, drop;

  @override
  bool operator ==(Object other) =>
      other is LoquetPalette &&
      other.body == body &&
      other.face == face &&
      other.feet == feet &&
      other.zzz == zzz &&
      other.accent == accent &&
      other.drop == drop;

  @override
  int get hashCode => Object.hash(body, face, feet, zzz, accent, drop);
}
