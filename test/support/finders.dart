import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Like `find.text`, but also matches `Text.rich` whose words equal [text]
/// (ignoring inline widgets such as a task card's checkbox).
Finder text(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data == text ||
          w.textSpan?.toPlainText(includePlaceholders: false) == text),
  description: 'text "$text"',
);
