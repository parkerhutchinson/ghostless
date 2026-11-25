import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// One choice of a [SlidingToggle].
final class ToggleSegment<T> {
  const ToggleSegment({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// The app's toggle (Board/List, Settings' tabs…): equal-width segments in
/// a bordered box, the selected one on the accent. Picking another slides
/// the accent across to it, left or right, the moment it's pressed;
/// [onChanged] comes once it has arrived, so whatever the choice changes
/// (a whole board, say) doesn't hold the slide up. No ripple or hover
/// fill: the slide is the feedback.
///
/// As wide as its widest segment times their number; given a tight width
/// (a stretched column), it fills it.
class SlidingToggle<T> extends StatefulWidget {
  const SlidingToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<ToggleSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  static const height = 32.0;
  static const duration = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  @override
  State<SlidingToggle<T>> createState() => _SlidingToggleState<T>();
}

class _SlidingToggleState<T> extends State<SlidingToggle<T>> {
  /// Where the accent is (or is sliding to): ahead of [widget.selected]
  /// while it slides.
  late T _selected = widget.selected;

  /// Reports the pick once the slide is done.
  Timer? _report;

  @override
  void didUpdateWidget(SlidingToggle<T> old) {
    super.didUpdateWidget(old);
    // Changed from outside (not by a press here): follow it.
    if (widget.selected != old.selected && _report == null) {
      _selected = widget.selected;
    }
  }

  @override
  void dispose() {
    _report?.cancel();
    super.dispose();
  }

  void _pick(T value) {
    if (value == _selected) return;
    setState(() => _selected = value);
    _report?.cancel();
    _report = Timer(SlidingToggle.duration, () {
      _report = null;
      if (mounted && widget.selected != _selected) widget.onChanged(_selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments;
    final selected = _selected;
    final n = segments.length;
    final index = segments.indexWhere((s) => s.value == selected);
    const duration = SlidingToggle.duration, curve = SlidingToggle.curve;
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: SlidingToggle.height,
      child: IntrinsicWidth(
        child: DecoratedBox(
          // The border drawn over the sliding fill, so it stays crisp.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: formRadius,
            border: Border.all(color: context.colors.cardBorder),
          ),
          child: ClipRRect(
            borderRadius: formRadius,
            child: ColoredBox(
              // The background color, so it reads over a background image.
              color: context.colors.surface,
              // Expand: the segments fill the toggle's full height (and
              // the width IntrinsicWidth settles on).
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (index >= 0)
                    Positioned.fill(
                      child: AnimatedAlign(
                        duration: duration,
                        curve: curve,
                        alignment: Alignment(
                          n == 1 ? 0 : -1 + 2 * index / (n - 1),
                          0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 1 / n,
                          heightFactor: 1,
                          child: ColoredBox(color: accent),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in segments)
                        Expanded(
                          child: _Segment(
                            segment: s,
                            selected: s.value == selected,
                            onTap: () => _pick(s.value),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.onTap,
  });
  final ToggleSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final _Segment(:segment, :selected, :onTap) = widget;
    final s = segment;
    // Dark on the accent, the text color off it; changing as the fill
    // slides under.
    final color = selected
        ? Theme.of(context).colorScheme.onPrimary
        : context.colors.text;
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // On press, not release: it slides the moment it's clicked.
          onTapDown: (_) => onTap(),
          // The sidebar rows' light hover shade, on the segments that
          // aren't picked (the picked one is on the accent).
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _hover && !selected
                ? Theme.of(context).hoverColor
                : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: SlidingToggle.duration,
                curve: SlidingToggle.curve,
                builder: (context, color, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    if (s.icon case final icon?)
                      Icon(icon, size: 16, color: color),
                    Text(
                      s.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
