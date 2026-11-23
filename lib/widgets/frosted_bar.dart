import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../layout.dart';
import '../settings/background.dart';
import 'blur.dart';

/// Height of a page header's row (title, view toggle, buttons), so every
/// page's [FrostedBar] is the same height.
const pageHeaderHeight = 40.0;

/// Space above and below a page header's row, inside its glass.
const _headerInset = titleBarHeight + 2;

/// A page's header bar: frosted glass (the background blurred under a
/// wash of the background color) across the pane's full width, from the
/// top of the window, so the title reads over any background image.
/// [child] sits below the title bar strip (which drags the window),
/// centered in the rest; a little space separates it from the page below.
/// With no background image there's nothing to frost: it's just the
/// header on the background color. Either way, a line along its bottom.
class FrostedBar extends StatelessWidget {
  const FrostedBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: _Glass(
        child: Padding(
          // As much space below as above, so it sits centered in the
          // glass (just below the title bar strip, which drags the window).
          padding: const EdgeInsets.fromLTRB(
            24,
            _headerInset,
            24,
            _headerInset,
          ),
          child: SizedBox(
            height: pageHeaderHeight,
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ),
      ),
    );
  }
}

/// A board column's or list section's heading on the same glass as
/// [FrostedBar] (frosted only over a background image, a line along its
/// bottom either way), square-cornered.
class FrostedHeader extends StatelessWidget {
  const FrostedHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.line = true,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// The line along the bottom; off where a border is right below anyway
  /// (a list section's box).
  final bool line;

  @override
  Widget build(BuildContext context) => _Glass(
    line: line,
    child: Padding(padding: padding, child: child),
  );
}

/// Frosted glass over a background image: the background blurred under a
/// wash of the background color. Either way, a line along the bottom in
/// a tint of the background color (the usual border line).
///
/// The blur is the background image itself, blurred once (see
/// [blurredImage]) and drawn lined up with the window's. Not a
/// BackdropFilter: it doesn't blur on this renderer (Impeller, MetalSDF),
/// nor inside a list's fade (a ShaderMask).
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.line = true});
  final Widget child;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final image = BackgroundImageScope.of(context);
    final frosted = image != null;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        // Tinted with the background color picked in Settings.
        color: frosted ? context.colors.surface.withValues(alpha: 0.5) : null,
        border: line
            ? Border(
                // A tint of the background color, frosted or not.
                bottom: BorderSide(color: context.colors.cardBorder),
              )
            : null,
      ),
      child: child,
    );
    if (!frosted) return box;
    final glass = Stack(
      children: [
        Positioned.fill(child: _BlurredBackground(image)),
        box,
      ],
    );
    return ClipRect(child: glass);
  }
}

/// [image] blurred, covering the window exactly as the background does,
/// shown through this box. Repaints as anything scrolls it.
class _BlurredBackground extends StatefulWidget {
  const _BlurredBackground(this.image);
  final ImageProvider image;

  @override
  State<_BlurredBackground> createState() => _BlurredBackgroundState();
}

class _BlurredBackgroundState extends State<_BlurredBackground> {
  final _positions = <ScrollPosition>[];
  late Future<ui.Image?> _blurred = blurredImage(widget.image);

  void _repaint() => context.findRenderObject()?.markNeedsPaint();

  @override
  void didUpdateWidget(_BlurredBackground old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _blurred = blurredImage(widget.image);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every scrollable it's in: scrolling moves it over the window
    // without repainting it, so it repaints itself.
    for (final p in _positions) {
      p.removeListener(_repaint);
    }
    _positions.clear();
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      _positions.add(scrollable.position..addListener(_repaint));
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  @override
  void dispose() {
    for (final p in _positions) {
      p.removeListener(_repaint);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _WindowAligned(
    window: MediaQuery.sizeOf(context),
    child: FutureBuilder<ui.Image?>(
      future: _blurred,
      // Until it's blurred (a moment, once per image): just the tint.
      builder: (context, snap) => RawImage(
        image: snap.data,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

/// Lays [child] out at the [window]'s size and paints it where the window's
/// top-left is, so it lines up with what's behind.
class _WindowAligned extends SingleChildRenderObjectWidget {
  const _WindowAligned({required this.window, super.child});
  final Size window;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWindowAligned(window);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWindowAligned renderObject,
  ) => renderObject.window = window;
}

class _RenderWindowAligned extends RenderProxyBox {
  _RenderWindowAligned(this._window);

  Size _window;
  set window(Size value) {
    if (value == _window) return;
    _window = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child?.layout(BoxConstraints.tight(_window));
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset - localToGlobal(Offset.zero));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
