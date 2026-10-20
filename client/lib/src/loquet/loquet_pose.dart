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

  /// [eyeX] (0 left to 1 right) only moves the eyes of [LoquetMood.watching].
  factory LoquetPose.of(LoquetMood mood, {double eyeX = 0.5}) => switch (mood) {
    LoquetMood.watching => LoquetPose(
      LoquetEyes.follow,
      LoquetMouth.smallO,
      lookX: eyeX.clamp(0, 1) * 12 - 6,
    ),
    LoquetMood.idle => const LoquetPose(LoquetEyes.open, LoquetMouth.smile),
    LoquetMood.covering => _covering,
    LoquetMood.peeking => _peeking,
    LoquetMood.happy => _happy,
    LoquetMood.sad => _sad,
    LoquetMood.alert => _alert,
    LoquetMood.connecting => _connecting,
    LoquetMood.search => _search,
    LoquetMood.offline => _offline,
    LoquetMood.sleep => _sleep,
    LoquetMood.sleepy => const LoquetPose(LoquetEyes.sleepy, LoquetMouth.tiny),
    LoquetMood.yawn => _yawn,
    LoquetMood.cheerful => _cheerful,
    LoquetMood.concerned => _concerned,
    LoquetMood.dizzy => const LoquetPose(LoquetEyes.spiral, LoquetMouth.zigzag),
  };

  static const _covering = LoquetPose(
    LoquetEyes.closed,
    LoquetMouth.flat,
    hands: LoquetHands.cover,
  );

  static const _peeking = LoquetPose(
    LoquetEyes.oneOpen,
    LoquetMouth.flat,
    hands: LoquetHands.peek,
  );

  static const _happy = LoquetPose(LoquetEyes.arcs, LoquetMouth.openSmile);

  static const _sad = LoquetPose(
    LoquetEyes.worried,
    LoquetMouth.frown,
    tone: LoquetTone.danger,
  );

  static const _alert = LoquetPose(
    LoquetEyes.wide,
    LoquetMouth.bigO,
    extras: {LoquetExtra.sweat},
    tone: LoquetTone.danger,
  );

  static const _connecting = LoquetPose(LoquetEyes.up, LoquetMouth.smallO);

  static const _search = LoquetPose(
    LoquetEyes.aside,
    LoquetMouth.smallO,
    extras: {LoquetExtra.magnifier},
  );

  static const _offline = LoquetPose(
    LoquetEyes.flat,
    LoquetMouth.frown,
    tone: LoquetTone.warn,
  );

  static const _sleep = LoquetPose(
    LoquetEyes.closed,
    LoquetMouth.flat,
    extras: {LoquetExtra.zzz},
  );

  static const _yawn = LoquetPose(
    LoquetEyes.squeezed,
    LoquetMouth.yawn,
    extras: {LoquetExtra.tear},
  );

  static const _cheerful = LoquetPose(LoquetEyes.cheerful, LoquetMouth.grin);

  static const _concerned = LoquetPose(LoquetEyes.glance, LoquetMouth.wavy);

  final LoquetEyes eyes;
  final LoquetMouth mouth;
  final LoquetHands hands;
  final Set<LoquetExtra> extras;
  final LoquetTone tone;

  /// Horizontal eye offset in viewBox units, from -6 to 6.
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
