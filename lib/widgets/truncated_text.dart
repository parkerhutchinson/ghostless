import 'package:material_ui/material_ui.dart';

/// One line of text that ends in "…" when it doesn't fit, and then (only
/// then) shows the whole text in a tooltip on hover.
///
/// Whether it's cut short is checked after each layout (comparing its
/// width with the text's full width), not with a LayoutBuilder, so it
/// works inside IntrinsicHeight rows like the list view's.
class TruncatedText extends StatefulWidget {
  const TruncatedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<TruncatedText> createState() => _TruncatedTextState();
}

class _TruncatedTextState extends State<TruncatedText> {
  bool _truncated = false;

  void _check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: DefaultTextStyle.of(context).style.merge(widget.style),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final truncated = painter.width > box.size.width + 0.5;
    painter.dispose();
    if (truncated != _truncated) setState(() => _truncated = truncated);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt (and checked again) when the window is resized.
    MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    return Tooltip(
      // An empty message shows no tooltip.
      message: _truncated ? widget.text : '',
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      ),
    );
  }
}
