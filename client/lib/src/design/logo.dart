// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

/// The U-shaped lock mark in [color], else the ambient icon colour; always square.
class UfLogo extends StatelessWidget {
  const UfLogo({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _LogoPainter(color ?? IconTheme.of(context).color!),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);

  final Color color;

  // The brand mark in a 100 by 100 viewBox; paint() scales it to the widget size.
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
    // A stretched box (a tight parent) never overflows: the mark fits its shortest side.
    canvas.scale(size.shortestSide / 100);
    canvas.drawPath(_mark, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}
