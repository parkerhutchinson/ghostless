import 'package:material_ui/material_ui.dart';

/// The text selection: a white highlight with black text on it, in every
/// text field, whatever the background or accent.
const selectionFill = Color(0xFFFFFFFF);
const selectedTextColor = Color(0xFF000000);

/// A text field's controller that draws its selected text black, on the
/// white highlight ([selectionFill], from the theme). Use it for every
/// text field: a plain [TextEditingController] leaves the selected text
/// in the text color, white on white.
class AppTextController extends TextEditingController {
  AppTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => withSelectedText(
    context,
    super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    ),
    selection,
  );
}

/// [span] (a text field's text) with the part in [selection] drawn in
/// [selectedTextColor]. Only while the field has focus: unfocused, the
/// highlight isn't shown, so neither is this.
TextSpan withSelectedText(
  BuildContext context,
  TextSpan span,
  TextSelection selection,
) {
  final field = context.widget;
  final focused = field is EditableText && field.focusNode.hasFocus;
  if (!focused || !selection.isValid || selection.isCollapsed) return span;
  final (start, end) = (selection.start, selection.end);
  var at = 0;
  const selected = TextStyle(color: selectedTextColor);

  InlineSpan walk(InlineSpan s) {
    if (s is! TextSpan) {
      at += 1; // A placeholder (WidgetSpan) is one character.
      return s;
    }
    final text = s.text ?? '';
    final from = at, to = at + text.length;
    at = to;
    final pieces = <InlineSpan>[];
    if (text.isNotEmpty) {
      final a = start.clamp(from, to) - from, b = end.clamp(from, to) - from;
      if (a == b) {
        pieces.add(TextSpan(text: text));
      } else {
        if (a > 0) pieces.add(TextSpan(text: text.substring(0, a)));
        pieces.add(TextSpan(text: text.substring(a, b), style: selected));
        if (b < text.length) pieces.add(TextSpan(text: text.substring(b)));
      }
    }
    final children = [for (final c in s.children ?? const []) walk(c)];
    return TextSpan(
      style: s.style,
      recognizer: s.recognizer,
      mouseCursor: s.mouseCursor,
      semanticsLabel: s.semanticsLabel,
      locale: s.locale,
      spellOut: s.spellOut,
      children: [...pieces, ...children],
    );
  }

  return walk(span) as TextSpan;
}
