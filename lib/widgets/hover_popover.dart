import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// Shows [popover] in a bubble while the pointer rests on [child]: below
/// it (above when there's no room below), with a little triangle pointing
/// at [child]'s middle. On the card shade (like the list rows and cards),
/// with a border and 4px corners; at most [maxWidth] wide, as tall as it needs.
/// Look only: the bubble doesn't take clicks.
class HoverPopover extends StatefulWidget {
  const HoverPopover({
    super.key,
    required this.child,
    required this.popover,
    this.enabled = true,
    this.maxWidth = 280,
    this.delay = const Duration(milliseconds: 250),
  });

  final Widget child;
  final Widget popover;

  /// Off: [child] alone, no bubble.
  final bool enabled;
  final double maxWidth;

  /// How long the pointer rests before the bubble shows.
  final Duration delay;

  @override
  State<HoverPopover> createState() => _HoverPopoverState();
}

class _HoverPopoverState extends State<HoverPopover> {
  final _portal = OverlayPortalController();
  Timer? _timer;

  void _enter() {
    if (!widget.enabled) return;
    _timer?.cancel();
    _timer = Timer(widget.delay, () {
      if (mounted) _portal.show();
    });
  }

  void _exit() {
    _timer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void didUpdateWidget(HoverPopover old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _exit();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// [child]'s box, in the overlay's coordinates.
  Rect? _target(BuildContext overlayContext) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (overlayContext) {
      final target = _target(overlayContext);
      if (target == null) return const SizedBox.shrink();
      return IgnorePointer(
        child: _PopoverLayout(
          target: target,
          maxWidth: widget.maxWidth,
          // The list rows' (and cards') shade.
          fill: context.colors.card,
          border: context.colors.formBorder,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: widget.popover,
          ),
        ),
      );
    },
    child: MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: widget.child,
    ),
  );
}

/// Places the bubble by [target] and draws it (box and triangle as one
/// outline) behind its content.
class _PopoverLayout extends SingleChildRenderObjectWidget {
  const _PopoverLayout({
    required this.target,
    required this.maxWidth,
    required this.fill,
    required this.border,
    super.child,
  });

  final Rect target;
  final double maxWidth;
  final Color fill;
  final Color border;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPopover(target, maxWidth, fill, border);

  @override
  void updateRenderObject(BuildContext context, _RenderPopover r) => r
    ..target = target
    ..maxWidth = maxWidth
    ..fill = fill
    ..border = border;
}

class _RenderPopover extends RenderShiftedBox {
  _RenderPopover(this._target, this._maxWidth, this._fill, this._border)
    : super(null);

  /// The triangle: how far it sticks out, and how wide its base is.
  static const _arrow = 7.0, _arrowBase = 14.0;

  /// Space kept from the window's edges.
  static const _margin = 8.0;

  Rect _target;
  set target(Rect v) {
    if (v == _target) return;
    _target = v;
    markNeedsLayout();
  }

  double _maxWidth;
  set maxWidth(double v) {
    if (v == _maxWidth) return;
    _maxWidth = v;
    markNeedsLayout();
  }

  Color _fill;
  set fill(Color v) {
    if (v == _fill) return;
    _fill = v;
    markNeedsPaint();
  }

  Color _border;
  set border(Color v) {
    if (v == _border) return;
    _border = v;
    markNeedsPaint();
  }

  /// Where the bubble's box went, and whether it's above the target.
  Rect _box = Rect.zero;
  bool _above = false;

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    final width = (size.width - 2 * _margin).clamp(0.0, _maxWidth);
    child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final h = child.size.height, w = child.size.width;
    final below = _target.bottom + _arrow;
    final above = _target.top - _arrow - h;
    // Below if it fits; else above if that fits better.
    _above = below + h > size.height - _margin && above >= _margin;
    final top = _above ? above : below;
    final left = (_target.center.dx - w / 2).clamp(
      _margin,
      (size.width - w - _margin).clamp(_margin, double.infinity),
    );
    _box = Rect.fromLTWH(left, top, w, h);
    (child.parentData! as BoxParentData).offset = _box.topLeft;
  }

  Path _outline() {
    final r = formRadius.topLeft.x;
    // The triangle's tip at the target's middle, its base kept clear of
    // the rounded corners.
    final x = _target.center.dx.clamp(
      _box.left + r + _arrowBase / 2,
      _box.right - r - _arrowBase / 2,
    );
    final edge = _above ? _box.bottom : _box.top;
    final tip = _above ? edge + _arrow : edge - _arrow;
    final triangle = Path()
      ..moveTo(x - _arrowBase / 2, edge)
      ..lineTo(x, tip)
      ..lineTo(x + _arrowBase / 2, edge)
      ..close();
    final box = Path()..addRRect(formRadius.toRRect(_box));
    return Path.combine(PathOperation.union, box, triangle);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final outline = _outline().shift(offset);
    context.canvas
      ..drawShadow(outline, Colors.black, 6, false)
      ..drawPath(outline, Paint()..color = _fill)
      ..drawPath(
        outline,
        Paint()
          ..color = _border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    super.paint(context, offset); // The content, at _box.topLeft.
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
