// SPDX-License-Identifier: Apache-2.0
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'loquet_pose.dart';

const _bodyData =
    'M20 8 H80 A4 4 0 0 1 84 12 V58 A34 34 0 0 1 16 58 V12 A4 4 0 0 1 20 8 Z M45 8 H55 V20 A5 5 0 0 1 45 20 Z';

/// The logo silhouette with its short top notch left open; viewBox 100 × 100.
@visibleForTesting
Path loquetBodyPath() => _path(_bodyData)..fillType = PathFillType.evenOdd;

// colours are irrelevant when only the outlines are read
const _none = Color(0x00000000);
const _shapesOnly = LoquetPalette(
  body: _none,
  face: _none,
  feet: _none,
  hand: _none,
  handLine: _none,
  zzz: _none,
  accent: _none,
  drop: _none,
);

/// Every shape of [accessory], for its bounds.
@visibleForTesting
Path loquetAccessoryPath(LoquetAccessory accessory) {
  final out = Path();
  for (final s in _accessory(accessory, _shapesOnly)) {
    out.addPath(s.path, Offset.zero);
  }
  return out;
}

/// The only code that draws Loquet: feet, body, face, extras, accessory, then hands over the accessory.
/// Shapes follow the mockup; viewBox 100 × 100 scaled to the size, hats may reach y = −50.
class LoquetPainter extends CustomPainter {
  const LoquetPainter({
    required this.pose,
    required this.palette,
    this.accessory,
    this.blink = 0,
    this.squash = 0,
  });

  final LoquetPose pose;
  final LoquetPalette palette;
  final LoquetAccessory? accessory;

  /// 0 open … 1 closed, for open eyes.
  final double blink;

  /// 0 … 1, squashes towards the feet.
  final double squash;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas
      ..save()
      ..scale(scale)
      ..translate(50, 96)
      ..scale(1 + 0.06 * squash, 1 - 0.12 * squash)
      ..translate(-50, -96);
    final c = palette;
    final feet = Paint()..color = c.feet;
    for (final x in [28.0, 58.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 88, 14, 8),
          const Radius.circular(4),
        ),
        feet,
      );
    }
    canvas.drawPath(loquetBodyPath(), Paint()..color = c.body);
    for (final s in _face()) {
      _draw(canvas, s);
    }
    if (accessory case final a?) {
      for (final s in _accessory(a, c)) {
        _draw(canvas, s);
      }
    }
    if (pose.hands != LoquetHands.none) {
      for (final s in _hands()) {
        _draw(canvas, s);
      }
    }
    canvas.restore();
  }

  List<_Shape> _face() {
    final face = palette.face;
    final body = palette.body;
    _Shape fill(String d, [Color? color]) => _fill(d, color ?? face);
    _Shape line(String d, [double width = 3.5]) => _line(d, face, width);
    final open = 1 - 0.85 * blink;
    List<_Shape> eyes(double dx, double dy, {bool left = true}) => [
      if (left) _ellipse(37 + dx, 42 + dy, 4.5, 6 * open, face),
      _ellipse(63 + dx, 42 + dy, 4.5, 6 * open, face),
    ];
    final shapes = <_Shape>[
      ...switch (pose.eyes) {
        LoquetEyes.open => eyes(pose.lookX, 0),
        LoquetEyes.follow => eyes(pose.lookX, 5),
        LoquetEyes.up => eyes(2, -3),
        LoquetEyes.aside => eyes(5, 0),
        LoquetEyes.oneOpen => eyes(0, 0, left: false),
        LoquetEyes.arcs => [line('M32 45 Q37 37 42 45 M58 45 Q63 37 68 45')],
        LoquetEyes.wide => [
          _circle(37, 42, 7, face),
          _circle(63, 42, 7, face),
          _circle(37, 42, 2.4, body),
          _circle(63, 42, 2.4, body),
        ],
        LoquetEyes.worried => [
          line('M31 39 L42 42 M69 39 L58 42'),
          _ellipse(37, 47, 3.5, 4, face),
          _ellipse(63, 47, 3.5, 4, face),
        ],
        LoquetEyes.closed => [line('M32 44 Q37 48 42 44 M58 44 Q63 48 68 44')],
        LoquetEyes.flat => [line('M32 42 H42 M58 42 H68')],
        LoquetEyes.spiral => [
          line(
            'M37 41 a1 1 0 1 1 -1 1 a2.5 2.5 0 1 1 2.5 2.5 a4 4 0 1 1 -4 -4 a5.5 5.5 0 1 1 5.5 5.5 '
            'M63 41 a1 1 0 1 1 -1 1 a2.5 2.5 0 1 1 2.5 2.5 a4 4 0 1 1 -4 -4 a5.5 5.5 0 1 1 5.5 5.5',
            1.8,
          ),
        ],
        LoquetEyes.squeezed => [
          line('M30 40 Q36 46 43 42 M57 42 Q64 46 70 40', 3.4),
          fill('M27 47 q-2 4 0.5 6 q3 -1 1.5 -6 Z', palette.drop),
        ],
        LoquetEyes.sleepy => [
          fill(
            'M32.5 43 A4.5 4.5 0 0 0 41.5 43 Z M58.5 43 A4.5 4.5 0 0 0 67.5 43 Z',
          ),
          line('M31 44 Q36 39.5 43 42.5 M69 44 Q64 39.5 57 42.5', 2.8),
        ],
        LoquetEyes.cheerful => [
          ...eyes(pose.lookX, 0),
          _circle(38.5 + pose.lookX, 39.5, 1.6, body),
          _circle(64.5 + pose.lookX, 39.5, 1.6, body),
        ],
        LoquetEyes.glance => [
          line('M30 38 L41 33 M70 38 L59 33', 3),
          _ellipse(39, 44, 4, 5.5, face),
          _ellipse(65, 44, 4, 5.5, face),
        ],
      },
      ...switch (pose.mouth) {
        LoquetMouth.smile => [line('M44 58 Q50 63 56 58')],
        LoquetMouth.openSmile => [fill('M41 56 Q50 67 59 56 Z')],
        LoquetMouth.smallO => [
          _circle(pose.eyes == LoquetEyes.aside ? 52 : 50, 59, 3.3, face),
        ],
        LoquetMouth.bigO => [_ellipse(50, 60, 4.5, 5.5, face)],
        LoquetMouth.flat => [line('M46 60 H54')],
        LoquetMouth.frown => [line('M44 61 Q50 56 56 61')],
        LoquetMouth.zigzag => [line('M42 60 l3 -3 l3 3 l3 -3 l3 3 l3 -3', 3)],
        LoquetMouth.yawn => [
          _ellipse(50, 63, 8, 12, face),
          _ellipse(50, 70, 5, 3.5, const Color(0xD9E57A87)),
        ],
        LoquetMouth.tiny => [_ellipse(50, 60, 2.6, 2, face)],
        LoquetMouth.grin => [line('M41 56 Q50 66 59 56')],
        LoquetMouth.wavy => [line('M44 60 q3 -3 6 0 q3 3 6 0', 3)],
      },
      for (final extra in pose.extras)
        ...switch (extra) {
          LoquetExtra.sweat => [
            _fill('M78 26 q4 6 0 9 q-4 -3 0 -9 Z', palette.drop),
          ],
          LoquetExtra.magnifier => [
            _ring(86, 70, 9, palette.feet, 4),
            _line('M92.5 76.5 L101 85', palette.feet, 5),
          ],
          // drawn as strokes, no font
          LoquetExtra.zzz => [
            _line('M84 7 H92 L84 16 H92', palette.zzz, 2.4),
            _line('M92 -1 H97.5 L92 6 H97.5', palette.zzz, 1.8),
          ],
          LoquetExtra.tear => const <_Shape>[], // part of the yawn
        },
    ];
    return shapes;
  }

  List<_Shape> _hands() {
    final covering = pose.hands == LoquetHands.cover;
    return [
      for (final (cx, dx, dy) in [
        (12.0, 25.0, -23.0),
        (88.0, covering ? -25.0 : -12.0, covering ? -23.0 : -2.0),
      ]) ...[
        _ellipse(cx + dx, 66 + dy, 9, 7.5, palette.hand),
        _ellipseRing(cx + dx, 66 + dy, 9, 7.5, palette.handLine, 1.6),
      ],
    ];
  }

  @override
  bool shouldRepaint(LoquetPainter old) =>
      old.pose != pose ||
      old.palette != palette ||
      old.accessory != accessory ||
      old.blink != blink ||
      old.squash != squash;
}

typedef _Shape = ({Path path, Color? fill, Color? stroke, double width});

void _draw(Canvas canvas, _Shape s) {
  if (s.fill case final color?) {
    canvas.drawPath(s.path, Paint()..color = color);
  }
  if (s.stroke case final color?) {
    canvas.drawPath(
      s.path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

_Shape _fill(String d, Color color) =>
    (path: _path(d), fill: color, stroke: null, width: 0);

_Shape _line(String d, Color color, double width) =>
    (path: _path(d), fill: null, stroke: color, width: width);

_Shape _ellipse(double cx, double cy, double rx, double ry, Color color) => (
  path: Path()
    ..addOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
    ),
  fill: color,
  stroke: null,
  width: 0,
);

_Shape _ellipseRing(
  double cx,
  double cy,
  double rx,
  double ry,
  Color color,
  double width,
) => (
  path: Path()
    ..addOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
    ),
  fill: null,
  stroke: color,
  width: width,
);

_Shape _circle(double cx, double cy, double r, Color color) =>
    _ellipse(cx, cy, r, r, color);

_Shape _ring(double cx, double cy, double r, Color color, double width) =>
    _ellipseRing(cx, cy, r, r, color, width);

_Shape _rect(
  double x,
  double y,
  double w,
  double h,
  double r,
  Color color, {
  Color? stroke,
}) => (
  path: Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
    ),
  fill: color,
  stroke: stroke,
  width: 1,
);

List<_Shape> _accessory(LoquetAccessory a, LoquetPalette palette) {
  const ink = Color(0xFF121715);
  const gold = Color(0xFFE7B53C);
  const red = Color(0xFFC0485C);
  const snow = Color(0xFFF4F7FA);
  const snowLine = Color(0xFFC7D0CC);
  switch (a) {
    case LoquetAccessory.hardHat:
      return [
        _fill('M14 20 Q14 -2 50 -2 Q86 -2 86 20 Z', gold),
        _fill(
          'M46 -1.6 Q50 -2.4 54 -1.6 L55 20 H45 Z',
          const Color(0xFFD29F2C),
        ),
        _line('M24 10 Q28 3 37 1', const Color(0xFFF6D57A), 2.4),
        _rect(12, 19, 76, 7, 3.5, const Color(0xFFC48E22)),
      ];
    case LoquetAccessory.woollyHat:
      return [
        _fill('M12 18 Q12 -9 50 -9 Q88 -9 88 18 Z', red),
        _line(
          'M27 -3 V16 M38 -7 V16 M50 -9 V16 M62 -7 V16 M73 -3 V16',
          const Color(0xFFB03A4E),
          2.2,
        ),
        _rect(9, 14, 82, 12, 6, snow, stroke: snowLine),
        (
          path: Path()
            ..addOval(
              Rect.fromCircle(center: const Offset(50, -12), radius: 7),
            ),
          fill: snow,
          stroke: snowLine,
          width: 1,
        ),
      ];
    case LoquetAccessory.partyHat:
      // tilted −12° around (50, 10)
      final tilt = Matrix4.identity()
        ..translateByDouble(50, 10, 0, 1)
        ..rotateZ(-12 * pi / 180)
        ..translateByDouble(-50, -10, 0, 1);
      _Shape turn(_Shape s) => (
        path: s.path.transform(tilt.storage),
        fill: s.fill,
        stroke: s.stroke,
        width: s.width,
      );
      return [
        turn(_fill('M30 14 L50 -36 L70 14 Z', palette.accent)),
        turn(_line('M36 0 L64 0 M41 -12 L59 -12 M45 -24 L55 -24', gold, 4.5)),
        turn(_circle(50, -38, 6, red)),
        turn(_line('M28 14 H72', gold, 3)),
      ];
    case LoquetAccessory.sunglasses:
      return [
        _fill(
          'M22 34 H46 Q47 50 35 50 Q23 50 22 34 Z M54 34 H78 Q77 50 65 50 Q53 50 54 34 Z',
          ink,
        ),
        _line('M20 34 H80', ink, 3.5),
        _line('M27 38 L32 38 M59 38 L64 38', palette.drop, 2.4),
      ];
    case LoquetAccessory.fakeNose:
      return [
        _line('M27 32 Q37 27 46 32 M54 32 Q63 27 73 32', ink, 4.5),
        _ring(37, 43, 9.5, ink, 3),
        _ring(63, 43, 9.5, ink, 3),
        _line('M46.5 42 Q50 39.5 53.5 42', ink, 3),
        (
          path: _path('M45 45 Q44 58 50 58 Q57 58 55 45 Z'),
          fill: const Color(0xFFE8A598),
          stroke: const Color(0xFFC97F72),
          width: 1.2,
        ),
        _fill(
          'M34 63 Q42 57 50 61 Q58 57 66 63 Q58 68 50 64.5 Q42 68 34 63 Z',
          const Color(0xFF3A2E28),
        ),
      ];
  }
}

final _token = RegExp(r'[MmLlHhVvQqAaZz]|-?(?:\d+\.?\d*|\.\d+)');

/// SVG path data (M L H V Q A Z, absolute and relative) as a [Path], so the mockup's shapes are used as written.
Path _path(String d) {
  final tokens = [for (final m in _token.allMatches(d)) m[0]!];
  final path = Path();
  var i = 0;
  var command = 'M';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp('[A-Za-z]').hasMatch(tokens[i])) command = tokens[i++];
    final relative = command == command.toLowerCase();
    final dx = relative ? x : 0.0, dy = relative ? y : 0.0;
    switch (command.toUpperCase()) {
      case 'M':
        x = dx + next();
        y = dy + next();
        path.moveTo(x, y);
        (startX, startY) = (x, y);
        command = relative ? 'l' : 'L'; // further pairs are lines
      case 'L':
        x = dx + next();
        y = dy + next();
        path.lineTo(x, y);
      case 'H':
        x = dx + next();
        path.lineTo(x, y);
      case 'V':
        y = dy + next();
        path.lineTo(x, y);
      case 'Q':
        final cx = dx + next(), cy = dy + next();
        x = dx + next();
        y = dy + next();
        path.quadraticBezierTo(cx, cy, x, y);
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final large = next() != 0, sweep = next() != 0;
        x = dx + next();
        y = dy + next();
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: large,
          clockwise: sweep,
        );
      case 'Z':
        path.close();
        (x, y) = (startX, startY);
    }
  }
  return path;
}
