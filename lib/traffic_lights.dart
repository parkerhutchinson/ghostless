import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Custom macOS traffic lights: gray at rest, regular colors with symbols
/// while the pointer is over the group (like the native hover behavior).
///
/// The native buttons are hidden in main.dart so these replace them.
class TrafficLights extends StatefulWidget {
  const TrafficLights({super.key});

  @override
  State<TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<TrafficLights> {
  bool _hovering = false;

  Window get _window => WindowManager.instance.getCurrent()!;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          _LightButton(
            kind: _Light.close,
            active: _hovering,
            onPressed: () => _window.close(),
          ),
          _LightButton(
            kind: _Light.minimize,
            active: _hovering,
            onPressed: () => _window.minimize(),
          ),
          _LightButton(
            kind: _Light.fullScreen,
            active: _hovering,
            onPressed: () => _window.isFullScreen = !_window.isFullScreen,
          ),
        ],
      ),
    );
  }
}

enum _Light {
  close(Color(0xFFFF5F57), Color(0xFFE2463F)),
  minimize(Color(0xFFFEBC2E), Color(0xFFE1A116)),
  fullScreen(Color(0xFF28C840), Color(0xFF1AAB29));

  const _Light(this.fill, this.border);
  final Color fill;
  final Color border;
}

// Solid grays, matched to the sidebar they sit on.
const _grayFill = Color(0xFF888B94);
const _grayBorder = Color(0xFF70747E);
const _diameter = 12.0;

class _LightButton extends StatelessWidget {
  const _LightButton({
    required this.kind,
    required this.active,
    required this.onPressed,
  });

  final _Light kind;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: _diameter,
        height: _diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? kind.fill : _grayFill,
          border: Border.all(
            color: active ? kind.border : _grayBorder,
            width: 0.5,
          ),
        ),
        child: active
            ? CustomPaint(painter: _GlyphPainter(kind))
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Draws the ×, − and full-screen arrows shown on hover.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind);
  final _Light kind;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = Color.lerp(kind.fill, Colors.black, 0.6)!
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    switch (kind) {
      case _Light.close:
        const d = 2.6;
        canvas.drawLine(
          c + const Offset(-d, -d),
          c + const Offset(d, d),
          paint,
        );
        canvas.drawLine(
          c + const Offset(-d, d),
          c + const Offset(d, -d),
          paint,
        );
      case _Light.minimize:
        canvas.drawLine(c + const Offset(-3, 0), c + const Offset(3, 0), paint);
      case _Light.fullScreen:
        final fill = Paint()..color = paint.color;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 3, c.dy - 3)
            ..lineTo(c.dx + 1, c.dy - 3)
            ..lineTo(c.dx - 3, c.dy + 1)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + 3, c.dy + 3)
            ..lineTo(c.dx - 1, c.dy + 3)
            ..lineTo(c.dx + 3, c.dy - 1)
            ..close(),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind;
}
