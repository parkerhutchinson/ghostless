import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../widgets/frosted_bar.dart';
import 'task.dart';
import 'task_repository.dart';
import 'tasks_page.dart' show TaskCardBuilder;
import '../widgets/bottom_fade.dart';
import '../widgets/left_menu_button.dart';

const _columnWidth = 350.0;
const _columnGap = 16.0;
const _boardPadding = 24.0;

/// Kanban board: the project's columns, left to right. Cards can be dragged
/// between columns and reordered within one; columns can be dragged by
/// their heading to reorder them, and added, renamed and deleted.
class TaskBoard extends StatelessWidget {
  const TaskBoard({
    super.key,
    required this.tasks,
    required this.repo,
    required this.projectId,
    required this.card,
    required this.onCreate,
    required this.columns,
    required this.onRenameColumn,
    required this.onMoveColumn,
    required this.onDeleteColumn,
    required this.onAddColumn,
    this.editingColumnId,
  });

  /// The project's tasks as placed on its board (every status is one of
  /// [columns]).
  final List<Task> tasks;
  final TaskRepository repo;

  /// The project shown; drops are positioned among its tasks.
  final String projectId;

  final TaskCardBuilder card;
  final ValueChanged<String> onCreate;

  /// This project's columns, left to right.
  final List<TaskColumn> columns;

  final void Function(String columnId, String name) onRenameColumn;

  /// Moves a column to an index (counted without it).
  final void Function(String columnId, int index) onMoveColumn;
  final ValueChanged<TaskColumn> onDeleteColumn;
  final VoidCallback onAddColumn;

  /// A column whose name opens for editing (one just added).
  final String? editingColumnId;

  /// Drops [dragged] on the column at [target]: it takes that column's
  /// place, and the columns in between shift over (left or right).
  void _dropColumn(TaskColumn dragged, int target) =>
      onMoveColumn(dragged.id, target);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // A little room at the bottom so a column's scrollbar stops short of
      // the window's edge; a full column fades out there (see _PanelScroll).
      padding: const EdgeInsets.fromLTRB(_boardPadding, 0, _boardPadding, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _columnGap,
        children: [
          for (final (i, column) in columns.indexed)
            ColumnDropTarget(
              accepts: (c) => c.id != column.id,
              onDrop: (c) => _dropColumn(c, i),
              child: _BoardColumn(
                column: column,
                tasks: tasks.where((t) => t.status == column.id).toList(),
                repo: repo,
                projectId: projectId,
                card: card,
                onCreate: () => onCreate(column.id),
                onRename: (name) => onRenameColumn(column.id, name),
                // A board always keeps one column.
                onDelete: columns.length < 2
                    ? null
                    : () => onDeleteColumn(column),
                startEditing: column.id == editingColumnId,
              ),
            ),
          // Dropping a column here moves it to the end.
          ColumnDropTarget(
            accepts: (c) => c.id != columns.last.id,
            onDrop: (c) => _dropColumn(c, columns.length - 1),
            child: AddColumnButton(onPressed: onAddColumn),
          ),
        ],
      ),
    );
  }
}

/// Accepts a dragged column, highlighting the whole column it's over (the
/// dragged column takes its place).
class ColumnDropTarget extends StatelessWidget {
  const ColumnDropTarget({
    super.key,
    required this.accepts,
    required this.onDrop,
    required this.child,
  });

  final bool Function(TaskColumn) accepts;
  final ValueChanged<TaskColumn> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskColumn>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (candidates.isNotEmpty)
            // A little wider than the column, into the gaps either side.
            Positioned(
              left: -6,
              right: -6,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.text.withValues(alpha: 0.06),
                    borderRadius: containerRadius,
                    border: Border.all(
                      color: context.colors.text.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "+ Add column": on the board, right of the last column; in the list
/// view, below the last section (with its own [label]).
class AddColumnButton extends StatelessWidget {
  const AddColumnButton({
    super.key,
    required this.onPressed,
    this.label = 'Add column',
    this.width = 200,
  });
  final VoidCallback onPressed;
  final String label;

  /// `double.infinity` fills the available width (the list view's).
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: width,
          // The accent, like the + button for a new task.
          child: FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Symbols.add, size: 18),
            label: Text(label),
          ),
        ),
      ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.column,
    required this.tasks,
    required this.repo,
    required this.projectId,
    required this.card,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.startEditing,
  });

  final TaskColumn column;
  final List<Task> tasks;
  final TaskRepository repo;
  final String projectId;
  final TaskCardBuilder card;
  final VoidCallback onCreate;
  final ValueChanged<String> onRename;

  /// Null when the column can't move that way (or be deleted).
  final VoidCallback? onDelete;
  final bool startEditing;

  /// Drops [dragged] just before [beforeId], or at the end when null.
  void _drop(Task dragged, String? beforeId) {
    final others = tasks.where((t) => t.id != dragged.id).toList();
    final index = beforeId == null
        ? others.length
        : others.indexWhere((t) => t.id == beforeId);
    repo.move(dragged.id, column.id, index, projectId: projectId);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _columnWidth,
      // No panel behind the column: cards sit straight on the background.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dragging the heading moves the whole column.
          Draggable<TaskColumn>(
            data: column,
            axis: Axis.horizontal,
            // The whole heading bar drags, gaps included (not just the
            // title and buttons).
            hitTestBehavior: HitTestBehavior.opaque,
            feedback: Material(
              color: context.colors.card,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: containerRadius,
                side: BorderSide(color: context.colors.cardBorder),
              ),
              child: SizedBox(
                width: _columnWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ColumnHeader(
                    column: column,
                    count: tasks.length,
                    onCreate: onCreate,
                    onRename: onRename,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.4,
              child: FrostedHeader(
                child: ColumnHeader(
                  column: column,
                  count: tasks.length,
                  onCreate: onCreate,
                  onRename: onRename,
                ),
              ),
            ),
            // On glass, like the page's header, so it reads over an image.
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: FrostedHeader(
                child: ColumnHeader(
                  column: column,
                  count: tasks.length,
                  onCreate: onCreate,
                  onRename: onRename,
                  onDelete: onDelete,
                  startEditing: startEditing,
                ),
              ),
            ),
          ),
          // The whole list area accepts drops at the end of the column;
          // each card's own target (which wins when hovered) drops before it.
          // The cards sit straight on the background, the column's full
          // width, with no panel or padding around them; the list scrolls
          // once the column is full. The whole area below the heading still
          // takes drops (at the end of the column).
          Expanded(
            child: DragTarget<Task>(
              onAcceptWithDetails: (d) => _drop(d.data, null),
              builder: (context, candidates, _) => Align(
                alignment: Alignment.topCenter,
                child: _PanelScroll(
                  builder: (controller) => ListView(
                    controller: controller,
                    shrinkWrap: true,
                    // Room to scroll the last card up out of the fade.
                    padding: const EdgeInsets.only(bottom: bottomFadeHeight),
                    children: [
                      for (final task in tasks) _cardSlot(task),
                      if (candidates.isNotEmpty) const _DropIndicator(),
                      if (tasks.isEmpty && candidates.isEmpty)
                        const _EmptyHint(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardSlot(Task task) {
    return DragTarget<Task>(
      key: ValueKey(task.id),
      onWillAcceptWithDetails: (d) => d.data.id != task.id,
      onAcceptWithDetails: (d) => _drop(d.data, task.id),
      builder: (context, candidates, _) {
        final card = this.card(task);
        return Padding(
          // Padding is inside the target so the gaps between cards count too.
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (candidates.isNotEmpty) const _DropIndicator(),
              Draggable<Task>(
                data: task,
                feedback: SizedBox(
                  width: _columnWidth, // the card's own width
                  child: Transform.rotate(
                    angle: 0.02,
                    child: this.card(task, lifted: true),
                  ),
                ),
                // A solid empty slot the size of the card it came from.
                childWhenDragging: Stack(
                  children: [
                    card,
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.emptySlot,
                          border: Border.all(color: context.colors.cardBorder),
                        ),
                      ),
                    ),
                  ],
                ),
                child: card,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A column's name (click it to rename), its task count, its ⋯ menu
/// (rename, move, delete) and +.
class ColumnHeader extends StatefulWidget {
  const ColumnHeader({
    super.key,
    required this.column,
    required this.count,
    required this.onCreate,
    required this.onRename,
    this.onDelete,
    this.startEditing = false,
    this.noun = 'column',
  });

  /// What the user calls it in the menu: a "column" on the board, a
  /// "section" in the list view.
  final String noun;

  final TaskColumn column;
  final int count;
  final VoidCallback onCreate;
  final ValueChanged<String> onRename;
  final VoidCallback? onDelete;

  /// Opens the name for editing right away (a column just added).
  final bool startEditing;

  String get title => column.title;

  @override
  State<ColumnHeader> createState() => _ColumnHeaderState();
}

class _ColumnHeaderState extends State<ColumnHeader> {
  static const _titleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  bool _editing = false;
  late final _name = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Clicking away saves, like Enter.
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finish(save: true);
    });
    if (widget.startEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _name.text = widget.title;
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  /// Saves (an empty name goes back to the default) or cancels (Escape).
  void _finish({required bool save}) {
    if (!_editing) return;
    setState(() => _editing = false);
    if (save && _name.text.trim() != widget.title) widget.onRename(_name.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Name and count take all the room left of the +, so the + is
          // always at the right edge; a long name is cut short first.
          Expanded(
            child: Row(
              spacing: 8,
              children: [
                Flexible(
                  child: _editing
                      ? CallbackShortcuts(
                          bindings: {
                            const SingleActivator(
                              LogicalKeyboardKey.escape,
                            ): () =>
                                _finish(save: false),
                          },
                          child: TextField(
                            controller: _name,
                            focusNode: _focus,
                            style: _titleStyle,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                            ),
                            onSubmitted: (_) => _finish(save: true),
                          ),
                        )
                      : Tooltip(
                          message: 'Click to rename, drag to move',
                          waitDuration: const Duration(milliseconds: 600),
                          child: InkWell(
                            onTap: _start,
                            // The heading drags the column (see _BoardColumn).
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: formRadius,
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _titleStyle,
                            ),
                          ),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.card,
                    borderRadius: formRadius,
                  ),
                  child: Text(
                    '${widget.count}',
                    style: TextStyle(fontSize: 12, color: context.colors.text),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Add task to ${widget.title}',
            // Same size and padding as the ⋯ next to it.
            iconSize: 17,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              fixedSize: const Size(26, 26),
              minimumSize: const Size(26, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: widget.onCreate,
            icon: Icon(Symbols.add),
          ),
          const SizedBox(width: 4),
          _ColumnMenu(
            noun: widget.noun,
            onRename: _start,
            onDelete: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

/// A column's ⋯ menu: Rename and Delete (disabled for the only column).
class _ColumnMenu extends StatelessWidget {
  const _ColumnMenu({
    required this.noun,
    required this.onRename,
    required this.onDelete,
  });

  final String noun;

  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<VoidCallback> item(
      String label,
      IconData icon,
      VoidCallback? action, {
      Color? color,
    }) => PopupMenuItem(
      value: action,
      enabled: action != null,
      height: 36,
      child: Row(
        spacing: 10,
        children: [
          Icon(icon, size: 18, color: action == null ? null : color),
          Text(label, style: TextStyle(color: action == null ? null : color)),
        ],
      ),
    );

    return LeftMenuButton<VoidCallback>(
      tooltip: '${noun[0].toUpperCase()}${noun.substring(1)} options',
      iconSize: 17,
      padding: EdgeInsets.zero,
      // Like the + beside it: no tile until hovered, then solid gray.
      style: context.colors.menuButtonStyle.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
              ? context.colors.hover
              : Colors.transparent,
        ),
      ),
      icon: Icon(Symbols.more_horiz),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item('Rename', Symbols.edit, onRename),
        item(
          'Delete $noun',
          Symbols.delete,
          onDelete,
          color: Colors.red.shade300,
        ),
      ],
    );
  }
}

/// A column's card list with a scrollbar only when the cards really
/// overflow (more than a pixel: sub-pixel rounding on high-density screens
/// shouldn't show one).
class _PanelScroll extends StatefulWidget {
  const _PanelScroll({required this.builder});
  final Widget Function(ScrollController controller) builder;

  @override
  State<_PanelScroll> createState() => _PanelScrollState();
}

class _PanelScrollState extends State<_PanelScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      // Replaces the automatic scrollbar with the one below.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _controller,
        // Shows only while the column scrolls: not on hovering where the
        // bar would be (which also means the thumb isn't draggable).
        interactive: false,
        notificationPredicate: (n) =>
            n.depth == 0 && n.metrics.maxScrollExtent > 1,
        // A full column fades out at the bottom.
        child: BottomFade(child: widget.builder(_controller)),
      ),
    );
  }
}

class _DropIndicator extends StatelessWidget {
  const _DropIndicator();

  @override
  Widget build(BuildContext context) => Container(
    height: 3,
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: context.colors.text,
      borderRadius: formRadius,
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => Container(
    height: 80,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      // The background color (no card shade, since there's no card), so
      // it reads over a background image.
      color: context.colors.surface,
      borderRadius: formRadius,
      border: Border.all(color: context.colors.cardBorder),
    ),
    child: Text(
      'No tasks',
      style: TextStyle(fontSize: 12.5, color: context.colors.mutedText),
    ),
  );
}
