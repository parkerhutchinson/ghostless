import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import 'frosted_bar.dart';

/// Every list's and column's heading title: 14px, semi-bold.
const listHeadingTitleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
);

/// The height of a heading's row (its buttons are 26 square), so every
/// heading is as tall as a board column's, with or without buttons.
const listHeadingRowHeight = 26.0;

/// Above and below a heading's row, inside the glass.
const listHeadingPadding = EdgeInsets.symmetric(vertical: 10);

/// The one heading style for lists and columns: the board's columns, the
/// list view's sections, Activity's days, the dashboard's sections, the
/// Company page's lists. See CLAUDE.md, "List and column headings".
///
/// On frosted glass, the title (14/w600) and its count in a chip, then
/// [actions] at the right. It sits right on its content, no gap under it.
/// [line] draws its own line along the bottom; leave it off when the
/// content below starts with a border of its own (a boxed list), so
/// there's one line, not two.
class ListHeading extends StatelessWidget {
  const ListHeading(
    this.title, {
    super.key,
    this.count,
    this.actions = const [],
    this.line = false,
    this.squareCount = false,
  });

  final String title;
  final int? count;

  /// Buttons at the right (26 square, or [listHeadingRowHeight] tall).
  final List<Widget> actions;
  final bool line;

  /// The count's chip without rounded corners, on the square pages
  /// (Activity, Company, the list view).
  final bool squareCount;

  @override
  Widget build(BuildContext context) => FrostedHeader(
    line: line,
    child: Padding(
      padding: listHeadingPadding,
      child: SizedBox(
        height: listHeadingRowHeight,
        child: Row(
          children: [
            // Title and count take the room left of the buttons, so the
            // buttons are at the right edge; a long title is cut short.
            Expanded(
              child: Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: listHeadingTitleStyle,
                    ),
                  ),
                  if (count case final n?) HeadingCount(n, square: squareCount),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    ),
  );
}

/// A heading's count, beside its title, on the card shade.
class HeadingCount extends StatelessWidget {
  const HeadingCount(this.count, {super.key, this.square = false});
  final int count;
  final bool square;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: square ? null : formRadius,
    ),
    child: Text(
      '$count',
      style: TextStyle(fontSize: 12, color: context.colors.text),
    ),
  );
}
