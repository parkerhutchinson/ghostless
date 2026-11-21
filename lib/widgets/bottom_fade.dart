import 'package:material_ui/material_ui.dart';

/// How far up from the bottom a scrolling list fades out.
const bottomFadeHeight = 64.0;

/// Fades the bottom [bottomFadeHeight] of a scrolling [child] to nothing
/// while there's more to scroll to below; scrolled to the end, nothing
/// fades. Used where lists run to the bottom of the window (board columns,
/// the list view).
class BottomFade extends StatefulWidget {
  const BottomFade({super.key, required this.child});

  /// Contains the scrollable (its own scroll, depth 0, is followed).
  final Widget child;

  @override
  State<BottomFade> createState() => _BottomFadeState();
}

class _BottomFadeState extends State<BottomFade> {
  /// More below the bottom edge: the bottom fades out.
  bool _more = false;

  bool _onMetrics(ScrollMetrics m) {
    final more = m.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, _more ? Colors.transparent : Colors.black],
            stops: [
              rect.height <= bottomFadeHeight
                  ? 0
                  : (rect.height - bottomFadeHeight) / rect.height,
              1,
            ],
          ).createShader(rect),
          child: widget.child,
        ),
      ),
    );
  }
}
