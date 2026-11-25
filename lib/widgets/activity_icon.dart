import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The Activity icon: a small ring inside a broken ring of four arcs
/// of different lengths (round ends, equal gaps), like ripples going out. Drawn, since Material
/// Symbols has nothing like it; sized and colored like an [Icon] (from
/// the [IconTheme] unless given), with the same line as the Symbols'
/// at weight 300.
class ActivityIcon extends StatelessWidget {
  const ActivityIcon({super.key, this.size, this.color});
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ActivityPainter(
          color ?? theme.color ?? DefaultTextStyle.of(context).style.color!,
        ),
      ),
    );
  }
}

class _ActivityPainter extends CustomPainter {
  const _ActivityPainter(this.color);
  final Color color;

  /// The outer ring's four arcs, uneven on purpose, with gaps of 31°
  /// between them, but 39° at the top right (it looked narrower). Start
  /// and sweep, in degrees clockwise from 3 o'clock.
  static const _arcs = [
    (241.0, 60.0), // top
    (340.0, 49.0), // top right
    (60.0, 36.0), // bottom
    (127.0, 83.0), // left
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      // Material Symbols' line at weight 300 (the app's), measured: 0.072
      // of the size (about 1.15px at 16).
      ..strokeWidth = s * 0.072;
    // Within the box like a Symbols glyph (a little in from the edges).
    final outer = s * 0.395, inner = s * 0.145;
    canvas.drawCircle(center, inner, paint);
    double rad(double deg) => deg * math.pi / 180;
    for (final (start, sweep) in _arcs) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outer),
        rad(start),
        rad(sweep),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ActivityPainter old) => old.color != color;
}
