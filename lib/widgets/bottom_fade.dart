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

/// A scroll view of one child whose bottom fades out ([BottomFade]), with
/// its scrollbar outside the fade so the scrollbar never fades with it.
/// Use it for any page that scrolls to the bottom of the window.
class BottomFadeScrollView extends StatefulWidget {
  const BottomFadeScrollView({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  State<BottomFadeScrollView> createState() => _BottomFadeScrollViewState();
}

class _BottomFadeScrollViewState extends State<BottomFadeScrollView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    // The automatic scrollbar would be drawn inside the fade.
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      controller: _scroll,
      child: BottomFade(
        // Not a SingleChildScrollView: that one snaps back from the Mac's
        // stretch past the end whenever it's laid out again (a hover
        // changing under the pointer is enough).
        child: CustomScrollView(
          controller: _scroll,
          shrinkWrap: true,
          slivers: [
            SliverPadding(
              padding: widget.padding ?? EdgeInsets.zero,
              sliver: SliverToBoxAdapter(child: widget.child),
            ),
          ],
        ),
      ),
    ),
  );
}
