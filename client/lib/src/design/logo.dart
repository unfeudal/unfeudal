// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

/// The "U serrure" mark in the ambient icon colour, always square.
class UfLogo extends StatelessWidget {
  const UfLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _LogoPainter(IconTheme.of(context).color!)),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);

  final Color color;

  // brand/logo/logo.svg, viewBox 0 0 100 100
  static final _mark = Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(20, 8)
    ..lineTo(80, 8)
    ..arcToPoint(const Offset(84, 12), radius: const Radius.circular(4))
    ..lineTo(84, 58)
    ..arcToPoint(const Offset(16, 58), radius: const Radius.circular(34))
    ..lineTo(16, 12)
    ..arcToPoint(const Offset(20, 8), radius: const Radius.circular(4))
    ..close()
    ..moveTo(44.5, 8)
    ..lineTo(55.5, 8)
    ..lineTo(55.5, 47.34)
    ..arcToPoint(
      const Offset(44.5, 47.34),
      radius: const Radius.circular(12),
      largeArc: true,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    canvas.drawPath(_mark, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}
