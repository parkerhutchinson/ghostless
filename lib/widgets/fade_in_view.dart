import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// A view's content fading in when it opens, like a project's board and
/// list (`TasksPage`): from nothing to full over [duration], eased out,
/// starting after the frame that builds it (not during: building a big
/// view can take longer than the fade).
///
/// Each frame moves the fade on by at most a 60fps frame's worth, so when
/// the first frames are slow the fade slows with them instead of being
/// over before it's seen. Give it a key to fade in again (another
/// project, say). Every view uses it: see CLAUDE.md, "Every view fades
/// in".
class FadeInView extends StatefulWidget {
  const FadeInView({
    super.key,
    required this.child,
    this.duration = fadeInDuration,
    this.onFaded,
  });

  final Widget child;
  final Duration duration;

  /// Called once the fade has finished: start what animates after it
  /// (a dashboard's numbers counting up, its avatars appearing).
  final VoidCallback? onFaded;

  /// How long a view takes to fade in (the board's).
  static const fadeInDuration = Duration(milliseconds: 250);

  @override
  State<FadeInView> createState() => _FadeInViewState();
}

class _FadeInViewState extends State<FadeInView> with TickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, value: 0);
  late final _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeOut);
  late final Ticker _ticker = createTicker(_tick);
  Duration? _last;

  static const _maxStep = Duration(microseconds: 16667);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ticker.start();
    });
  }

  void _tick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    if (last == null) return; // The first tick: no time has passed yet.
    final step = elapsed - last;
    final capped = step > _maxStep ? _maxStep : step;
    final value =
        _fade.value + capped.inMicroseconds / widget.duration.inMicroseconds;
    _fade.value = value.clamp(0.0, 1.0);
    if (value >= 1) {
      _ticker.stop();
      widget.onFaded?.call();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
