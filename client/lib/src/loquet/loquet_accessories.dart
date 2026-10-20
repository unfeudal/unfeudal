// SPDX-License-Identifier: Apache-2.0
part of 'loquet_painter.dart';

const _ink = Color(0xFF121715);
const _gold = Color(0xFFE7B53C);
const _red = Color(0xFFC0485C);
const _snow = Color(0xFFF4F7FA);
const _snowLine = Color(0xFFC7D0CC);

List<_Shape> _accessory(LoquetAccessory a, LoquetPalette palette) {
  switch (a) {
    case LoquetAccessory.hardHat:
      return [
        _fill('M14 20 Q14 -2 50 -2 Q86 -2 86 20 Z', _gold),
        _fill(
          'M46 -1.6 Q50 -2.4 54 -1.6 L55 20 H45 Z',
          const Color(0xFFD29F2C),
        ),
        _line('M24 10 Q28 3 37 1', const Color(0xFFF6D57A), 2.4),
        _rect(const Rect.fromLTWH(12, 19, 76, 7), 3.5, const Color(0xFFC48E22)),
      ];
    case LoquetAccessory.woollyHat:
      return [
        _fill('M12 18 Q12 -9 50 -9 Q88 -9 88 18 Z', _red),
        _line(
          'M27 -3 V16 M38 -7 V16 M50 -9 V16 M62 -7 V16 M73 -3 V16',
          const Color(0xFFB03A4E),
          2.2,
        ),
        _rect(const Rect.fromLTWH(9, 14, 82, 12), 6, _snow, stroke: _snowLine),
        (
          path: Path()
            ..addOval(
              Rect.fromCircle(center: const Offset(50, -12), radius: 7),
            ),
          fill: _snow,
          stroke: _snowLine,
          width: 1,
        ),
      ];
    case LoquetAccessory.partyHat:
      return _partyHat(palette);
    case LoquetAccessory.sunglasses:
      return [
        _fill(
          'M22 34 H46 Q47 50 35 50 Q23 50 22 34 Z M54 34 H78 Q77 50 65 50 Q53 50 54 34 Z',
          _ink,
        ),
        _line('M20 34 H80', _ink, 3.5),
        _line('M27 38 L32 38 M59 38 L64 38', palette.drop, 2.4),
      ];
    case LoquetAccessory.fakeNose:
      return _fakeNose();
  }
}

List<_Shape> _partyHat(LoquetPalette palette) {
  // Tilted -12 degrees around (50, 10).
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
    turn(_line('M36 0 L64 0 M41 -12 L59 -12 M45 -24 L55 -24', _gold, 4.5)),
    turn(_circle(const Offset(50, -38), 6, _red)),
    turn(_line('M28 14 H72', _gold, 3)),
  ];
}

List<_Shape> _fakeNose() => [
  _line('M27 32 Q37 27 46 32 M54 32 Q63 27 73 32', _ink, 4.5),
  _ring(const Offset(37, 43), 9.5, _ink, width: 3),
  _ring(const Offset(63, 43), 9.5, _ink, width: 3),
  _line('M46.5 42 Q50 39.5 53.5 42', _ink, 3),
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
