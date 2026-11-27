import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../widgets/hover_popover.dart';
import 'task_card.dart';

/// How many of the chips (widths in order) fit in [maxWidth] on one line,
/// [gap] apart, leaving room for a "+N" chip ([moreWidth] of how many are
/// left out) when not all do. At least one when there are any: it's cut
/// short ("…") rather than hidden.
int chipsThatFit(
  List<double> widths,
  double maxWidth,
  double Function(int hidden) moreWidth, {
  double gap = 4,
}) {
  final total =
      widths.fold(0.0, (a, w) => a + w) + gap * math.max(0, widths.length - 1);
  if (total <= maxWidth) return widths.length;
  var used = 0.0;
  for (var k = 0; k < widths.length; k++) {
    final next = used + (k == 0 ? 0 : gap) + widths[k];
    if (next + gap + moreWidth(widths.length - k - 1) > maxWidth) {
      return math.max(k, 1);
    }
    used = next;
  }
  return widths.length;
}

/// A list row's labels on one line: as many as fit, then "+N" for the
/// rest. Hovering shows them all in a bubble (only when some are hidden).
class LabelLine extends StatelessWidget {
  const LabelLine({super.key, required this.tags, required this.projectId});

  final List<String> tags;

  /// The project whose label colors they're in: the task's origin.
  final String? projectId;

  @override
  Widget build(BuildContext context) => ChipLine(
    chips: [for (final tag in tags) LabelChip(tag, projectId: projectId)],
  );
}

/// [chips] on one line (a list row's labels, its other projects): as many
/// as fit, then "+N" for the rest; hovering shows them all in a bubble
/// (only when some are hidden). Only one, too long: it's cut short.
class ChipLine extends StatefulWidget {
  const ChipLine({super.key, required this.chips});

  final List<Widget> chips;

  @override
  State<ChipLine> createState() => _ChipLineState();
}

class _ChipLineState extends State<ChipLine> {
  /// Some don't fit: the bubble is offered.
  bool _cut = false;

  void _cutChanged(bool cut) {
    if (cut == _cut) return;
    // Found during layout: rebuilt after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && cut != _cut) setState(() => _cut = cut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chips = widget.chips;
    return HoverPopover(
      enabled: _cut,
      popover: Wrap(spacing: 4, runSpacing: 4, children: chips),
      child: _LabelLineLayout(
        moreFill: context.colors.hover,
        moreStyle: DefaultTextStyle.of(context).style.merge(
          TextStyle(
            fontSize: 11.5,
            height: chipLineHeight,
            leadingDistribution: TextLeadingDistribution.even,
            color: context.colors.text,
          ),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        onCutChanged: _cutChanged,
        children: chips,
      ),
    );
  }
}

class _LabelLineLayout extends MultiChildRenderObjectWidget {
  const _LabelLineLayout({
    required this.moreFill,
    required this.moreStyle,
    required this.textScaler,
    required this.onCutChanged,
    required super.children,
  });

  final Color moreFill;
  final TextStyle moreStyle;
  final TextScaler textScaler;
  final ValueChanged<bool> onCutChanged;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLabelLine()
    ..moreFill = moreFill
    ..moreStyle = moreStyle
    ..textScaler = textScaler
    ..onCutChanged = onCutChanged;

  @override
  void updateRenderObject(BuildContext context, _RenderLabelLine r) => r
    ..moreFill = moreFill
    ..moreStyle = moreStyle
    ..textScaler = textScaler
    ..onCutChanged = onCutChanged;
}

class _LineParentData extends ContainerBoxParentData<RenderBox> {
  /// Laid out and painted (it fits).
  bool shown = false;
}

class _RenderLabelLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LineParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LineParentData> {
  static const _gap = 4.0;

  /// The "+N" chip's padding, like a label chip's.
  static const _morePadding = EdgeInsets.fromLTRB(7, 3, 7, 3);

  late Color moreFill;
  late ValueChanged<bool> onCutChanged;

  TextStyle? _moreStyle;
  set moreStyle(TextStyle v) {
    if (v == _moreStyle) return;
    _moreStyle = v;
    markNeedsLayout();
  }

  TextScaler _textScaler = TextScaler.noScaling;
  set textScaler(TextScaler v) {
    if (v == _textScaler) return;
    _textScaler = v;
    markNeedsLayout();
  }

  /// The "+N" text when some are hidden; null when all fit.
  TextPainter? _more;
  Rect _moreBox = Rect.zero;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LineParentData) {
      child.parentData = _LineParentData();
    }
  }

  TextPainter _moreText(int hidden) => TextPainter(
    text: TextSpan(text: '+$hidden', style: _moreStyle),
    textDirection: TextDirection.ltr,
    textScaler: _textScaler,
    maxLines: 1,
  )..layout();

  double _moreWidth(int hidden) =>
      _moreText(hidden).width + _morePadding.horizontal;

  List<RenderBox> get _children {
    final list = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      list.add(child);
      child = childAfter(child);
    }
    return list;
  }

  // One chip's height (they're all alike), for the row to size itself.
  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;
  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(0.0, (a, c) => a + c.getMaxIntrinsicWidth(height) + _gap);

  @override
  void performLayout() {
    final children = _children;
    final maxWidth = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxWidth);
    final widths = [
      for (final c in children) c.getMaxIntrinsicWidth(double.infinity),
    ];
    final fit = chipsThatFit(widths, maxWidth, _moreWidth, gap: _gap);
    final hidden = children.length - fit;
    _more = hidden > 0 ? _moreText(hidden) : null;
    final moreWidth = hidden > 0 ? _moreWidth(hidden) : 0.0;

    var x = 0.0, height = 0.0;
    for (final (i, child) in children.indexed) {
      final data = child.parentData! as _LineParentData;
      data.shown = i < fit;
      if (!data.shown) {
        child.layout(const BoxConstraints.tightFor(width: 0, height: 0));
        continue;
      }
      // The only one shown, and too long: cut short to leave room for +N.
      final room = maxWidth - x - (hidden > 0 ? moreWidth + _gap : 0);
      child.layout(
        fit == 1 ? loose.copyWith(maxWidth: math.max(0, room)) : loose,
        parentUsesSize: true,
      );
      data.offset = Offset(x, 0);
      x += child.size.width + _gap;
      height = math.max(height, child.size.height);
    }
    if (_more case final more?) {
      final h = math.max(height, more.height + _morePadding.vertical);
      _moreBox = Rect.fromLTWH(
        x,
        (h - more.height - _morePadding.vertical) / 2,
        moreWidth,
        more.height + _morePadding.vertical,
      );
      height = h;
    }
    // Chips centered on the line.
    for (final child in children) {
      final data = child.parentData! as _LineParentData;
      if (data.shown) {
        data.offset = Offset(data.offset.dx, (height - child.size.height) / 2);
      }
    }
    size = constraints.constrain(
      Size(maxWidth.isFinite ? maxWidth : x, height),
    );
    onCutChanged(hidden > 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _children) {
      final data = child.parentData! as _LineParentData;
      if (data.shown) context.paintChild(child, offset + data.offset);
    }
    if (_more case final more?) {
      final box = _moreBox.shift(offset);
      context.canvas.drawRRect(
        formRadius.toRRect(box),
        Paint()..color = moreFill,
      );
      more.paint(
        context.canvas,
        box.topLeft + Offset(_morePadding.left, _morePadding.top),
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _children.reversed) {
      final data = child.parentData! as _LineParentData;
      if (!data.shown) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (r, p) => child.hitTest(r, position: p),
      );
      if (hit) return true;
    }
    return false;
  }
}
