// SPDX-License-Identifier: Apache-2.0
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'loquet_pose.dart';

part 'loquet_accessories.dart';

const _bodyData =
    'M20 8 H80 A4 4 0 0 1 84 12 V58 A34 34 0 0 1 16 58 V12 A4 4 0 0 1 20 8 Z M45 8 H55 V20 A5 5 0 0 1 45 20 Z';

/// The logo silhouette with its short top notch left open; viewBox 100 by 100.
@visibleForTesting
Path loquetBodyPath() => _path(_bodyData)..fillType = PathFillType.evenOdd;

/// The only code that draws Loquet: feet, body, face, extras, accessory, then hands over the accessory.
/// The viewBox is 100 by 100, scaled to the size; hats may reach y = -50.
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

  /// From 0 (open) to 1 (closed), for open eyes.
  final double blink;

  /// From 0 to 1, squashes towards the feet.
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
    final feet = Paint()..color = palette.feet;
    for (final x in [28.0, 58.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 88, 14, 8),
          const Radius.circular(4),
        ),
        feet,
      );
    }
    canvas.drawPath(loquetBodyPath(), Paint()..color = palette.body);
    for (final s in _face()) {
      _draw(canvas, s);
    }
    if (accessory case final a?) {
      for (final s in _accessory(a, palette)) {
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

  List<_Shape> _face() => [
    ..._eyes(),
    ..._mouth(),
    for (final extra in pose.extras) ..._extra(extra),
  ];

  List<_Shape> _eyes() {
    final face = palette.face;
    final body = palette.body;
    _Shape fill(String d, [Color? color]) => _fill(d, color ?? face);
    _Shape line(String d, [double width = 3.5]) => _line(d, face, width);
    final open = 1 - 0.85 * blink;
    final eye = Radius.elliptical(4.5, 6 * open);
    List<_Shape> eyes(double dx, double dy, {bool left = true}) => [
      if (left) _ellipse(Offset(37 + dx, 42 + dy), eye, face),
      _ellipse(Offset(63 + dx, 42 + dy), eye, face),
    ];
    return switch (pose.eyes) {
      LoquetEyes.open => eyes(pose.lookX, 0),
      LoquetEyes.follow => eyes(pose.lookX, 5),
      LoquetEyes.up => eyes(2, -3),
      LoquetEyes.aside => eyes(5, 0),
      LoquetEyes.oneOpen => eyes(0, 0, left: false),
      LoquetEyes.arcs => [line('M32 45 Q37 37 42 45 M58 45 Q63 37 68 45')],
      LoquetEyes.wide => [
        _circle(const Offset(37, 42), 7, face),
        _circle(const Offset(63, 42), 7, face),
        _circle(const Offset(37, 42), 2.4, body),
        _circle(const Offset(63, 42), 2.4, body),
      ],
      LoquetEyes.worried => [
        line('M31 39 L42 42 M69 39 L58 42'),
        _ellipse(const Offset(37, 47), const Radius.elliptical(3.5, 4), face),
        _ellipse(const Offset(63, 47), const Radius.elliptical(3.5, 4), face),
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
        _circle(Offset(38.5 + pose.lookX, 39.5), 1.6, body),
        _circle(Offset(64.5 + pose.lookX, 39.5), 1.6, body),
      ],
      LoquetEyes.glance => [
        line('M30 38 L41 33 M70 38 L59 33', 3),
        _ellipse(const Offset(39, 44), const Radius.elliptical(4, 5.5), face),
        _ellipse(const Offset(65, 44), const Radius.elliptical(4, 5.5), face),
      ],
    };
  }

  List<_Shape> _mouth() {
    final face = palette.face;
    _Shape fill(String d, [Color? color]) => _fill(d, color ?? face);
    _Shape line(String d, [double width = 3.5]) => _line(d, face, width);
    return switch (pose.mouth) {
      LoquetMouth.smile => [line('M44 58 Q50 63 56 58')],
      LoquetMouth.openSmile => [fill('M41 56 Q50 67 59 56 Z')],
      LoquetMouth.smallO => [
        _circle(Offset(pose.eyes == LoquetEyes.aside ? 52 : 50, 59), 3.3, face),
      ],
      LoquetMouth.bigO => [
        _ellipse(const Offset(50, 60), const Radius.elliptical(4.5, 5.5), face),
      ],
      LoquetMouth.flat => [line('M46 60 H54')],
      LoquetMouth.frown => [line('M44 61 Q50 56 56 61')],
      LoquetMouth.zigzag => [line('M42 60 l3 -3 l3 3 l3 -3 l3 3 l3 -3', 3)],
      LoquetMouth.yawn => [
        _ellipse(const Offset(50, 63), const Radius.elliptical(8, 12), face),
        _ellipse(
          const Offset(50, 70),
          const Radius.elliptical(5, 3.5),
          const Color(0xD9E57A87),
        ),
      ],
      LoquetMouth.tiny => [
        _ellipse(const Offset(50, 60), const Radius.elliptical(2.6, 2), face),
      ],
      LoquetMouth.grin => [line('M41 56 Q50 66 59 56')],
      LoquetMouth.wavy => [line('M44 60 q3 -3 6 0 q3 3 6 0', 3)],
    };
  }

  List<_Shape> _extra(LoquetExtra extra) => switch (extra) {
    LoquetExtra.sweat => [_fill('M78 26 q4 6 0 9 q-4 -3 0 -9 Z', palette.drop)],
    LoquetExtra.magnifier => [
      _ring(const Offset(86, 70), 9, palette.feet, width: 4),
      _line('M92.5 76.5 L101 85', palette.feet, 5),
    ],
    // drawn as strokes, no font
    LoquetExtra.zzz => [
      _line('M84 7 H92 L84 16 H92', palette.zzz, 2.4),
      _line('M92 -1 H97.5 L92 6 H97.5', palette.zzz, 1.8),
    ],
    // The tear is drawn as part of the yawn.
    LoquetExtra.tear => const <_Shape>[],
  };

  List<_Shape> _hands() {
    final covering = pose.hands == LoquetHands.cover;
    const radius = Radius.elliptical(9, 7.5);
    return [
      for (final (cx, dx, dy) in [
        (12.0, 25.0, -23.0),
        (88.0, covering ? -25.0 : -12.0, covering ? -23.0 : -2.0),
      ]) ...[
        _ellipse(Offset(cx + dx, 66 + dy), radius, palette.body),
        _ellipseRing(
          Offset(cx + dx, 66 + dy),
          radius,
          palette.face,
          width: 1.6,
        ),
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

Path _oval(Offset center, Radius radius) => Path()
  ..addOval(
    Rect.fromCenter(center: center, width: radius.x * 2, height: radius.y * 2),
  );

_Shape _ellipse(Offset center, Radius radius, Color color) =>
    (path: _oval(center, radius), fill: color, stroke: null, width: 0);

_Shape _ellipseRing(
  Offset center,
  Radius radius,
  Color color, {
  required double width,
}) => (path: _oval(center, radius), fill: null, stroke: color, width: width);

_Shape _circle(Offset center, double r, Color color) =>
    _ellipse(center, Radius.circular(r), color);

_Shape _ring(Offset center, double r, Color color, {required double width}) =>
    _ellipseRing(center, Radius.circular(r), color, width: width);

_Shape _rect(Rect rect, double r, Color color, {Color? stroke}) => (
  path: Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r))),
  fill: color,
  stroke: stroke,
  width: 1,
);

final _token = RegExp(r'[MmLlHhVvQqAaZz]|-?(?:\d+\.?\d*|\.\d+)');

// SVG path data (M L H V Q A Z, absolute and relative) as a Path, so the shapes are kept as SVG strings.
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
        // SVG treats further coordinate pairs after a move as lines.
        command = relative ? 'l' : 'L';
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
