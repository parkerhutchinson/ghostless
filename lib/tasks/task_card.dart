import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../projects/project_logo.dart';
import '../app_theme.dart';
import 'due_date.dart';
import 'label_colors.dart';
import 'task.dart';
import 'task_repository.dart';
import '../widgets/left_menu_button.dart';
import '../widgets/truncated_text.dart';

/// Line height for the text in tags and project labels: a fixed height with
/// the extra space split evenly above and below, so the label sits in the
/// middle of the chip (and lines up with its icons).
const _chipLineHeight = 14 / 11.5;

/// A task on the board or in the list. Tapping opens it; the round button
/// checks it off (it stays in its column: tasks move only by dragging); the
/// ⋯ menu, shown on hover, removes it from this project or deletes it.
class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.repo,
    this.onOpen,
    this.onDelete,
    this.onRemoveFromProject,
    this.multiHomes = const [],
    this.completed = false,
    this.onToggleCompleted,
    this.onToggleSubtask,
    this.onAssign,
    this.subtasksExpanded = false,
    this.onToggleSubtasks,
    this.lifted = false,
    this.showAssignee = true,
  });

  /// Shows the assignee's avatar. Off on a personal project, where every
  /// task is its owner's.
  final bool showAssignee;

  /// Its subtasks are shown. They start collapsed: a toggle after the
  /// title (like the list view's) shows them.
  final bool subtasksExpanded;
  final VoidCallback? onToggleSubtasks;

  final Task task;
  final TaskRepository repo;

  /// Assigns the task to a profile (null: nobody), from the avatar's menu.
  final ValueChanged<String?>? onAssign;

  /// Checks a subtask off (or unchecks it), by id.
  final ValueChanged<String>? onToggleSubtask;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  /// Checked off on the board shown (it stays in its column).
  final bool completed;
  final VoidCallback? onToggleCompleted;

  /// Takes the task out of the project being shown. Only offered when it's
  /// also in another project.
  final VoidCallback? onRemoveFromProject;

  /// The projects the task was multi-homed to (not its origin). Not shown
  /// on the card; its menu says Delete removes it from all of them.
  final List<Project> multiHomes;

  /// Drawn raised, as while being dragged.
  final bool lifted;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _hover = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final TaskCard(:task, :repo, :onOpen, :onDelete, :lifted) = widget;
    final card = Material(
      color: context.colors.card,
      elevation: lifted ? 12 : 0,
      shadowColor: Colors.black,
      // Square: task cards have no rounded corners.
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        mouseCursor: SystemMouseCursors.click,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (task.images.isNotEmpty)
              Image.file(
                repo.imageFile(task.images.first),
                height: 160,
                fit: BoxFit.cover,
                cacheWidth: 600,
                // A line under the image, separating it from the text.
                // (Not on the error case, which shows nothing.)
                frameBuilder: (_, child, _, _) => DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: context.colors.cardBorder),
                    ),
                  ),
                  child: child,
                ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _Body(
                task: task,
                completed: widget.completed,
                onToggleCompleted: widget.onToggleCompleted,
                onToggleSubtask: widget.onToggleSubtask,
                onAssign: widget.onAssign,
                showAssignee: widget.showAssignee,
                subtasksExpanded: widget.subtasksExpanded,
                onToggleSubtasks: widget.onToggleSubtasks,
              ),
            ),
          ],
        ),
      ),
    );
    if (onDelete == null && widget.onRemoveFromProject == null) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          card,
          // Stays while its menu is open, even though the pointer has left
          // the card; otherwise the menu's choice would be dropped.
          if (_hover || _menuOpen)
            Positioned(
              top: 6,
              right: 6,
              child: _CardMenu(
                onDelete: onDelete,
                onRemoveFromProject: widget.onRemoveFromProject,
                shared: widget.multiHomes.isNotEmpty,
                onOpenChanged: (open) => setState(() => _menuOpen = open),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widths of the list view's table columns. Title, Due, Tags and Projects
/// share the width by flex, so they all grow and shrink with the window;
/// the menu is fixed.
abstract final class TaskTable {
  /// The checkbox's width ([DoneButton]'s full size) and the space between
  /// it and the title.
  static const checkbox = taskCheckboxSize + 4;
  static const titleGap = 6.0;

  static const menu = 34.0;
  static const titleFlex = 8,
      dueFlex = 3,
      tagsFlex = 3,
      projectsFlex = 3,
      assigneeFlex = 3;
  static const gap = 12.0;

  /// Space between a column line and the content on each side of it: the
  /// same as the table's left edge to "Title", so every column's label and
  /// content start the same distance in.
  static const cellPadding = 12.0;
  static const height = 44.0;

  /// The cells of a header or row with a 1px column line between them,
  /// [cellPadding] clear on each side. The last cell (the ⋯ menu) has no
  /// line before it, just a [gap].
  static List<Widget> withLines(BuildContext context, List<Widget> cells) {
    final line = SizedBox(
      width: 2 * cellPadding,
      child: Center(
        child: SizedBox(
          width: 1,
          height: double.infinity,
          child: ColoredBox(color: context.colors.cardBorder),
        ),
      ),
    );
    return [
      for (final (i, cell) in cells.indexed) ...[
        if (i > 0) i == cells.length - 1 ? const SizedBox(width: gap) : line,
        cell,
      ],
    ];
  }

  /// The column names, in a bordered box, fixed above the list. "Title"
  /// starts at the far left: the checkbox is part of the title column.
  /// Without the Assignee column ([showAssignee] off) on a personal
  /// project, like its rows.
  static Widget header(BuildContext context, {bool showAssignee = true}) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: context.colors.text,
    );
    // A DecoratedBox (not a Container), so the 1px border doesn't push the
    // labels out of line with the rows' columns. On the background color,
    // so it reads over a background image.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: cellPadding),
        child: SizedBox(
          height: 32,
          child: Row(
            children: withLines(context, [
              Expanded(
                flex: titleFlex,
                child: Text('Title', style: style),
              ),
              if (showAssignee)
                Expanded(
                  flex: assigneeFlex,
                  child: Text('Assignee', style: style),
                ),
              Expanded(
                flex: dueFlex,
                child: Text('Due', style: style),
              ),
              Expanded(
                flex: tagsFlex,
                child: Text('Labels', style: style),
              ),
              Expanded(
                flex: projectsFlex,
                child: Text('Projects', style: style),
              ),
              SizedBox(width: menu),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A task as one line of the list view's table: done checkbox, title, due
/// date, tags and other projects in columns ([TaskTable]), and the ⋯ menu
/// on hover. Click it to open the task. Same callbacks as [TaskCard].
class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    this.onOpen,
    this.onDelete,
    this.onRemoveFromProject,
    this.multiHomes = const [],
    this.completed = false,
    this.onToggleCompleted,
    this.expanded = false,
    this.onToggleExpanded,
    this.onAssign,
    this.showAssignee = true,
  });

  /// Assigns the task to a profile (null: nobody), from the Assignee cell.
  final ValueChanged<String?>? onAssign;

  /// Has an Assignee cell. Off on a personal project, where every task is
  /// its owner's.
  final bool showAssignee;

  final Task task;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onRemoveFromProject;
  final List<Project> multiHomes;
  final bool completed;
  final VoidCallback? onToggleCompleted;

  /// Its subtasks are shown under it (the list view draws them).
  final bool expanded;

  /// Shows or hides the subtasks: a toggle after the title, when it has
  /// any.
  final VoidCallback? onToggleExpanded;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _hover = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final TaskRow(:task, :completed) = widget;
    final hasMenu =
        widget.onDelete != null || widget.onRemoveFromProject != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover || _menuOpen
            ? context.colors.rowHover
            : Colors.transparent,
        // Square: the highlight fills the row edge to edge, between the
        // table's lines.
        child: InkWell(
          onTap: widget.onOpen,
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TaskTable.cellPadding,
            ),
            // At least [TaskTable.height]; taller when the tags wrap onto
            // more lines. IntrinsicHeight lets the column lines run the
            // row's full height.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: TaskTable.height),
              child: IntrinsicHeight(
                child: Row(
                  children: TaskTable.withLines(context, [
                    // The checkbox is inside the title column, so the
                    // header's "Title" sits above it.
                    Expanded(
                      flex: TaskTable.titleFlex,
                      child: Row(
                        spacing: TaskTable.titleGap,
                        children: [
                          SizedBox(
                            width: TaskTable.checkbox,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: DoneButton(
                                size: taskCheckboxSize,
                                done: completed,
                                onPressed: widget.onToggleCompleted,
                              ),
                            ),
                          ),
                          Flexible(
                            // The system font's line box has more room above the
                            // capitals than below, so centered text sits 0.6px
                            // low; nudged up to line up with the checkbox and chips.
                            child: Transform.translate(
                              offset: const Offset(0, -0.6),
                              // The full title in a tooltip when cut short.
                              child: TruncatedText(
                                task.title,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w400,
                                  color: completed
                                      ? context.colors.mutedText
                                      : null,
                                  decoration: completed
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: context.colors.text,
                                ),
                              ),
                            ),
                          ),
                          if (task.subtasks.isNotEmpty)
                            _SubtaskToggle(
                              subtasks: task.subtasks,
                              expanded: widget.expanded,
                              onPressed: widget.onToggleExpanded,
                            ),
                        ],
                      ),
                    ),
                    if (widget.showAssignee)
                      Expanded(
                        flex: TaskTable.assigneeFlex,
                        child: _AssigneeLabel(
                          assigneeId: task.assigneeId,
                          onChanged: widget.onAssign,
                        ),
                      ),
                    // A date too long for the column ends in "…".
                    Expanded(
                      flex: TaskTable.dueFlex,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: task.dueDate == null
                            ? null
                            : _DueLabel(task: task, completed: completed),
                      ),
                    ),
                    Expanded(
                      flex: TaskTable.tagsFlex,
                      // Tags wrap onto new lines (the row grows to fit).
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tag in task.tags)
                              LabelChip(tag, projectId: task.originId),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: TaskTable.projectsFlex,
                      // Like the card: one label per line when they don't
                      // fit side by side, and a name too long for the
                      // column ends in "…".
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final p in widget.multiHomes)
                              _MultiHomeLabel(project: p),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: TaskTable.menu,
                      child: hasMenu && (_hover || _menuOpen)
                          ? _CardMenu(
                              onDelete: widget.onDelete,
                              onRemoveFromProject: widget.onRemoveFromProject,
                              shared: widget.multiHomes.isNotEmpty,
                              onOpenChanged: (open) =>
                                  setState(() => _menuOpen = open),
                            )
                          : null,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ⋯ menu button (like a project's in the sidebar), shown on hover, holding the card's actions: Delete in
/// the task's origin project, Remove from this project where it's
/// multi-homed.
class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.onDelete,
    required this.onRemoveFromProject,
    required this.shared,
    required this.onOpenChanged,
  });
  final VoidCallback? onDelete;
  final VoidCallback? onRemoveFromProject;

  /// The task is in other projects too, so Delete removes it from all.
  final bool shared;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    // Same as the ⋯ on a project in the sidebar. Its gray tile also keeps a
    // long title from showing through.
    return LeftMenuButton<VoidCallback>(
      tooltip: 'Task options',
      iconSize: 17,
      padding: EdgeInsets.zero,
      style: context.colors.menuButtonStyle,
      icon: Icon(Symbols.more_horiz),
      onOpened: () => onOpenChanged(true),
      onCanceled: () => onOpenChanged(false),
      onSelected: (action) {
        onOpenChanged(false);
        action();
      },
      constraints: const BoxConstraints(minWidth: 200),
      itemBuilder: (_) => [
        if (onRemoveFromProject case final remove?)
          PopupMenuItem(
            value: remove,
            height: 36,
            child: const Row(
              spacing: 10,
              children: [
                Icon(Symbols.remove_circle, size: 18),
                Text('Remove from this project'),
              ],
            ),
          ),
        if (onDelete case final delete?)
          PopupMenuItem(
            value: delete,
            height: 36,
            child: Row(
              spacing: 10,
              children: [
                const SizedBox(width: 18), // No icon; in line with the rest.
                Text(
                  shared ? 'Delete from all projects' : 'Delete',
                  style: TextStyle(color: Colors.red.shade300),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.task,
    this.completed = false,
    this.onToggleCompleted,
    this.onToggleSubtask,
    this.onAssign,
    this.showAssignee = true,
    this.subtasksExpanded = false,
    this.onToggleSubtasks,
  });
  final Task task;
  final bool showAssignee;
  final bool subtasksExpanded;
  final VoidCallback? onToggleSubtasks;
  final bool completed;
  final VoidCallback? onToggleCompleted;
  final ValueChanged<String>? onToggleSubtask;
  final ValueChanged<String?>? onAssign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        // The checkbox is inline with the title, like the first word of a
        // paragraph, so long titles wrap underneath it.
        Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DoneButton(
                    size: taskCheckboxSize,
                    done: completed,
                    onPressed: onToggleCompleted,
                  ),
                ),
              ),
              TextSpan(
                text: task.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  color: completed ? context.colors.mutedText : null,
                  decoration: completed ? TextDecoration.lineThrough : null,
                  // The line stands out; the text stays muted.
                  decorationColor: context.colors.text,
                ),
              ),
              // Shows or hides the subtasks, at the end of the title.
              if (task.subtasks.isNotEmpty)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _SubtaskToggle(
                      subtasks: task.subtasks,
                      expanded: subtasksExpanded,
                      onPressed: onToggleSubtasks,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // No description: it's only shown in the task form.
        // The subtasks as a tree, in their order (rearranged in the form
        // or the list view).
        if (task.subtasks.isNotEmpty && subtasksExpanded)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, sub) in task.subtasks.indexed)
                SubtaskLine(
                  subtask: sub,
                  last: i == task.subtasks.length - 1,
                  onToggle: onToggleSubtask == null
                      ? null
                      : () => onToggleSubtask!(sub.id),
                ),
            ],
          ),
        // The tags, then the assignee and due date at the bottom. (The
        // other projects are only listed in the list view and the form.)
        if (task.tags.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tag in task.tags)
                LabelChip(tag, projectId: task.originId),
            ],
          ),
        // Last, under everything else: the assignee at the left (a
        // button that opens a menu of every profile), the due date at the
        // right.
        if (task.dueDate != null ||
            task.attachments.isNotEmpty ||
            (showAssignee && (task.assigneeId != null || onAssign != null)))
          Row(
            children: [
              if (showAssignee)
                AssigneeButton(
                  assigneeId: task.assigneeId,
                  onChanged: onAssign,
                ),
              // All the room after the avatar, so a long date only ends
              // in "…" when it truly doesn't fit.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 10,
                  children: [
                    if (task.dueDate != null)
                      Flexible(
                        child: _DueLabel(
                          task: task,
                          completed: completed,
                          outlined: false,
                        ),
                      ),
                    // How many files are attached, after the date.
                    if (task.attachments.isNotEmpty)
                      _AttachmentCount(count: task.attachments.length),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// When the task is due: "Nov 20" or "Nov 20, 2:30 PM" (never the year or
/// weekday). Once a day or more past due (and not checked off)
/// it says how late instead: "Due yesterday", "3 days overdue".
class _DueLabel extends StatelessWidget {
  const _DueLabel({
    required this.task,
    required this.completed,
    this.outlined = true,
  });

  /// Drawn as a chip with a border (the list view); without one it's plain
  /// text, flush with the card's edge (cards).
  final bool outlined;

  /// A checked-off task is never shown as overdue.
  final bool completed;
  final Task task;

  @override
  Widget build(BuildContext context) {
    final date = task.dueDate!;
    final now = DateTime.now();
    final l = MaterialLocalizations.of(context);
    // "Nov 20": no weekday, and no year, whichever year it is.
    final day = l.formatShortMonthDay(date);
    final time = task.dueTime;
    final dateText = time == null ? day : '$day, ${formatTime(time)}';
    // Past due (and not checked off): says how late instead of the date,
    // which shows on hover. Not colored red.
    final late = !completed && task.isOverdue(now)
        ? overdueLabel(date, now)
        : null;
    final color = context.colors.text;
    final label = Container(
      padding: outlined
          ? const EdgeInsets.fromLTRB(6, 3, 7, 3)
          : const EdgeInsets.symmetric(vertical: 3),
      decoration: outlined
          ? BoxDecoration(
              borderRadius: formRadius,
              // A little stronger than the table's lines, so the chip
              // stands out.
              border: Border.all(color: context.colors.formBorder),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(Symbols.calendar_today, size: 11, color: color),
          // Never wider than its column: ellipsized rather than overflowing.
          Flexible(
            // The full text in a tooltip when cut short.
            child: TruncatedText(
              late ?? dateText,
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                height: _chipLineHeight,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ],
      ),
    );
    if (late == null) return label;
    return Tooltip(message: 'Due $dateText', child: label);
  }
}

/// A paperclip and how many files a task has attached, styled like the
/// due date beside it.
class _AttachmentCount extends StatelessWidget {
  const _AttachmentCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.text;
    return Tooltip(
      message: '$count attachment${count == 1 ? '' : 's'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            Icon(Symbols.attach_file, size: 13, color: color),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                height: _chipLineHeight,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the task's other projects: a colored dot and its name.
class _MultiHomeLabel extends StatelessWidget {
  const _MultiHomeLabel({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 7, 3),
      decoration: BoxDecoration(
        borderRadius: formRadius,
        // A little stronger than the table's lines, so the chip stands out.
        border: Border.all(color: context.colors.formBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          ProjectIcon(project: project, size: 12),
          // A long name is cut short instead of overflowing the card.
          Flexible(
            child: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: context.colors.text,
                height: _chipLineHeight,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diameter of a task's done checkbox: the same as the assignee avatar.
const taskCheckboxSize = 20.0;

/// Round checkbox: an outline when open, a white circle with the check in
/// the card's color when checked off.
class DoneButton extends StatelessWidget {
  const DoneButton({
    super.key,
    required this.done,
    this.onPressed,
    this.size = 15,
  });
  final bool done;
  final VoidCallback? onPressed;

  /// Diameter. A task's own checkbox matches the assignee avatar
  /// ([taskCheckboxSize]); subtasks use the smaller default.
  final double size;

  @override
  Widget build(BuildContext context) {
    // White, or near-black on a light background.
    final fill = context.colors.text;
    return Tooltip(
      message: done ? 'Mark as not complete' : 'Mark as complete',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? fill : context.colors.card,
                border: Border.all(
                  color: done ? fill : context.colors.mutedText,
                  width: 1.5,
                ),
              ),
              child: done
                  ? Icon(
                      Symbols.check,
                      size: size * 2 / 3,
                      color: context.colors.card,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small colored label, in its color in [projectId] (the task's origin;
/// see [LabelColors]), or [color] when given (one being picked).
class LabelChip extends StatelessWidget {
  const LabelChip(
    this.tag, {
    super.key,
    required this.projectId,
    this.onDeleted,
    this.color,
  });
  final String tag;

  /// The project whose colors it's in: its task's origin.
  final String? projectId;
  final VoidCallback? onDeleted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? LabelColors.of(context, tag, projectId);
    return Container(
      padding: EdgeInsets.fromLTRB(7, 3, onDeleted == null ? 7 : 3, 3),
      decoration: BoxDecoration(
        color: labelFill(color),
        borderRadius: formRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: _chipLineHeight,
                leadingDistribution: TextLeadingDistribution.even,
                fontWeight: FontWeight.w400,
                color: labelText(color),
              ),
            ),
          ),
          if (onDeleted != null)
            InkWell(
              onTap: onDeleted,
              borderRadius: formRadius,
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(Symbols.close, size: 13, color: labelText(color)),
              ),
            ),
        ],
      ),
    );
  }
}

/// After a list row's title: a chevron and how many subtasks are done
/// ("1/3"). Click to show or hide them under the row.
class _SubtaskToggle extends StatefulWidget {
  const _SubtaskToggle({
    required this.subtasks,
    required this.expanded,
    this.onPressed,
  });
  final List<Subtask> subtasks;
  final bool expanded;
  final VoidCallback? onPressed;

  @override
  State<_SubtaskToggle> createState() => _SubtaskToggleState();
}

class _SubtaskToggleState extends State<_SubtaskToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final subtasks = widget.subtasks;
    final done = subtasks.where((s) => s.done).length;
    final hovered = _hovered && widget.onPressed != null;
    return Tooltip(
      message: widget.expanded ? 'Hide subtasks' : 'Show subtasks',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          // Its own hover, stronger than the card's (which is shaded too
          // while the pointer's over it), with an outline.
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
            decoration: BoxDecoration(
              color: hovered ? context.colors.hoverStrong : null,
              borderRadius: formRadius,
              border: Border.all(
                color: hovered ? context.colors.cardBorder : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Icon(
                  widget.expanded ? Symbols.expand_more : Symbols.chevron_right,
                  size: 16,
                ),
                Text(
                  '$done/${subtasks.length}',
                  style: TextStyle(fontSize: 11.5, color: context.colors.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One subtask in a tree: a line down from the task (the trunk, under the
/// task's checkbox) with a branch out to the subtask's checkbox, then its
/// title. The last subtask's trunk stops at its branch, closing the tree.
class SubtaskLine extends StatelessWidget {
  const SubtaskLine({
    super.key,
    required this.subtask,
    required this.last,
    this.onToggle,
    this.trunkX = 9.5,
    this.branchEnd = 26,
    this.verticalPadding = 3,
    this.fontSize = 12.5,
  });

  final Subtask subtask;

  /// The last subtask: the trunk ends here.
  final bool last;
  final VoidCallback? onToggle;

  /// Where the trunk runs, from the left edge: under the task's checkbox.
  final double trunkX;

  /// Where the branch ends and the subtask's checkbox starts.
  final double branchEnd;

  /// Space above and below the checkbox.
  final double verticalPadding;
  final double fontSize;

  /// [DoneButton]'s full height (circle plus its padding).
  static const _checkHeight = 19.0;

  @override
  Widget build(BuildContext context) {
    final done = subtask.done;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: branchEnd,
            child: CustomPaint(
              painter: _BranchPainter(
                trunkX: trunkX,
                branchY: verticalPadding + _checkHeight / 2,
                last: last,
                color: context.colors.formBorder,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            child: Align(
              alignment: Alignment.topCenter,
              child: DoneButton(done: done, onPressed: onToggle),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              // The first line's middle level with the checkbox's.
              padding: EdgeInsets.only(
                top: verticalPadding + (_checkHeight - fontSize * 1.35) / 2,
                bottom: verticalPadding,
              ),
              child: Text(
                subtask.title,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.35,
                  color: done ? context.colors.mutedText : context.colors.text,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: context.colors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchPainter extends CustomPainter {
  const _BranchPainter({
    required this.trunkX,
    required this.branchY,
    required this.last,
    required this.color,
  });
  final double trunkX;
  final double branchY;
  final bool last;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // 1px lines on whole pixels, so they stay crisp.
    final x = trunkX.floorToDouble();
    final y = branchY.floorToDouble();
    canvas.drawRect(
      Rect.fromLTRB(x, 0, x + 1, last ? y + 1 : size.height),
      paint,
    );
    canvas.drawRect(Rect.fromLTRB(x, y, size.width - 3, y + 1), paint);
  }

  @override
  bool shouldRepaint(_BranchPainter old) =>
      old.trunkX != trunkX ||
      old.branchY != branchY ||
      old.last != last ||
      old.color != color;
}

/// The list view's Assignee cell: the avatar button (see
/// [AssigneeButton]) and their name ("…" when the name is too long).
class _AssigneeLabel extends StatelessWidget {
  const _AssigneeLabel({required this.assigneeId, this.onChanged});
  final String? assigneeId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final profile = ProfilesScope.maybeOf(context)?.find(assigneeId);
    return Row(
      spacing: 6,
      children: [
        AssigneeButton(assigneeId: assigneeId, onChanged: onChanged),
        if (profile != null)
          Flexible(
            child: TruncatedText(
              profile.displayName,
              style: TextStyle(fontSize: 12, color: context.colors.text),
            ),
          ),
      ],
    );
  }
}
