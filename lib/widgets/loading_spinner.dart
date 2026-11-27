import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// A turning quarter circle: "loading". Unlike [CircularProgressIndicator]
/// (whose arc starts as a dot and grows), it's a whole arc from its first
/// frame, so it reads as loading even when it's only up briefly, or the
/// app is busy and it can't turn (building a big board).
class LoadingSpinner extends StatefulWidget {
  const LoadingSpinner({super.key, this.size = 22});
  final double size;

  @override
  State<LoadingSpinner> createState() => _LoadingSpinnerState();
}

class _LoadingSpinnerState extends State<LoadingSpinner>
    with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: RotationTransition(
      turns: _turns,
      child: CustomPaint(painter: _Arc(context.colors.mutedText)),
    ),
  );
}

class _Arc extends CustomPainter {
  _Arc(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // A faint full ring, with the turning arc on it.
    canvas.drawOval(rect, paint..color = color.withValues(alpha: 0.2));
    canvas.drawArc(rect, -pi / 2, pi / 2, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_Arc old) => old.color != color;
}
