import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../widgets/frosted_bar.dart';
import 'task.dart';
import 'task_editor.dart' show taskEditorWidth;
import 'task_repository.dart';
import 'tasks_page.dart' show TaskCardBuilder;
import '../widgets/bottom_fade.dart';
import '../widgets/left_menu_button.dart';
import '../widgets/selected_text.dart';
import '../widgets/list_heading.dart';

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
    this.openTask,
  });

  /// The task open in the form: its column scrolls to show its card
  /// (opened from a reminder, search or Activity, it may be out of view).
  final ValueListenable<String?>? openTask;

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
                openTask: openTask,
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
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.08),
                    borderRadius: containerRadius,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
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
    required this.openTask,
  });

  final ValueListenable<String?>? openTask;
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
                  // Every card laid out, not just the ones in view (as a
                  // ListView would): the column's height is then exact
                  // from the start, so the scrollbar doesn't jitter. A
                  // lazy list guesses the height of cards it hasn't laid
                  // out yet, and cards vary a lot (images, labels,
                  // subtasks), so its guess, and the thumb, kept changing
                  // as it scrolled.
                  //
                  // A sliver scroll view, not a SingleChildScrollView: that
                  // one snaps back from the Mac's stretch past the end
                  // whenever it's laid out again, and a card's hover
                  // changing (the pointer over the gap between cards) lays
                  // it out, so the scrollbar jumped mid-stretch.
                  builder: (controller) => CustomScrollView(
                    controller: controller,
                    // As tall as the cards, like the column's area allows.
                    shrinkWrap: true,
                    slivers: [
                      SliverPadding(
                        // Room to scroll the last card up out of the fade.
                        padding: const EdgeInsets.only(
                          bottom: bottomFadeHeight,
                        ),
                        sliver: SliverToBoxAdapter(
                          // Painted once and moved as it scrolls, instead
                          // of every card repainted each frame.
                          child: RepaintBoundary(
                            child: _CardList(
                              controller: controller,
                              tasks: tasks,
                              slot: _cardSlot,
                              openTask: openTask,
                              trailing: [
                                if (candidates.isNotEmpty)
                                  const _DropIndicator(),
                                if (tasks.isEmpty && candidates.isEmpty)
                                  const _EmptyHint(),
                              ],
                            ),
                          ),
                        ),
                      ),
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
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  /// Its rows are hidden (folded into the heading). List view only.
  final bool collapsed;

  /// Collapses or expands it, from the ⋯ menu; none on the board.
  final VoidCallback? onToggleCollapsed;

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
  static const _titleStyle = listHeadingTitleStyle;

  bool _editing = false;
  late final _name = AppTextController();
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
    // The one list heading style (see ListHeading), with an editable
    // name: same padding, title, count and 26px buttons.
    return Padding(
      padding: listHeadingPadding,
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
                HeadingCount(widget.count),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Add task to ${widget.title}',
            // Same size and padding as the ⋯ next to it.
            iconSize: 17,
            padding: EdgeInsets.zero,
            style: headerButtonFill(context).merge(
              IconButton.styleFrom(
                fixedSize: const Size(26, 26),
                minimumSize: const Size(26, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            onPressed: widget.onCreate,
            icon: Icon(Symbols.add),
          ),
          const SizedBox(width: 4),
          _ColumnMenu(
            noun: widget.noun,
            onRename: _start,
            onDelete: widget.onDelete,
            collapsed: widget.collapsed,
            onToggleCollapsed: widget.onToggleCollapsed,
          ),
        ],
      ),
    );
  }
}

/// A column heading's + and ⋯: no tile until hovered (or pressed), then
/// the count's shade beside them, with no tint over it.
ButtonStyle headerButtonFill(BuildContext context) => ButtonStyle(
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)
        ? context.colors.card
        : Colors.transparent,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
);

/// A column's ⋯ menu: Collapse or Expand (list view sections), Rename,
/// and Delete (disabled for the only column).
class _ColumnMenu extends StatelessWidget {
  const _ColumnMenu({
    required this.noun,
    required this.onRename,
    required this.onDelete,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  final String noun;

  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<VoidCallback> item(
      String label,
      // Null for none (Delete): a gap the icon's width keeps the label
      // in line with the others.
      IconData? icon,
      VoidCallback? action, {
      Color? color,
    }) => PopupMenuItem(
      value: action,
      enabled: action != null,
      height: 36,
      child: Row(
        spacing: 10,
        children: [
          if (icon == null)
            const SizedBox(width: 18)
          else
            Icon(icon, size: 18, color: action == null ? null : color),
          Text(label, style: TextStyle(color: action == null ? null : color)),
        ],
      ),
    );

    return LeftMenuButton<VoidCallback>(
      tooltip: '${noun[0].toUpperCase()}${noun.substring(1)} options',
      iconSize: 17,
      padding: EdgeInsets.zero,
      // Like the + beside it: no tile until hovered.
      style: headerButtonFill(context).merge(context.colors.menuButtonStyle),
      icon: Icon(Symbols.more_horiz),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (onToggleCollapsed case final toggle?)
          collapsed
              ? item('Expand $noun', Symbols.unfold_more, toggle)
              : item('Collapse $noun', Symbols.unfold_less, toggle),
        item('Rename', Symbols.edit, onRename),
        item('Delete $noun', null, onDelete, color: Colors.red.shade300),
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
      // The accent (Settings), like the other highlights.
      color: Theme.of(context).colorScheme.primary,
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

/// A column's cards, every one taking its real height (so the column's
/// height, and the scrollbar, are exact: no jitter), but only the cards
/// in or near view are built. The rest are empty boxes of the height
/// their card had when it was last laid out. Without this, anything that
/// rebuilds every card (a theme change: each of its animation's frames)
/// costs as much as the whole column, hundreds of cards on a big project.
///
/// A card is built (and measured) when it's near the view; cards never
/// measured are built a batch a frame until all are.
class _CardList extends StatefulWidget {
  const _CardList({
    required this.controller,
    required this.tasks,
    required this.slot,
    required this.trailing,
    required this.openTask,
  });

  /// When it's one of [tasks], its card is scrolled into view.
  final ValueListenable<String?>? openTask;
  final ScrollController controller;
  final List<Task> tasks;
  final Widget Function(Task task) slot;
  final List<Widget> trailing;

  @override
  State<_CardList> createState() => _CardListState();
}

class _CardListState extends State<_CardList> {
  /// Which half-screen the view is at: rebuilt when it moves to another.
  int _band = -1;
  bool _remeasured = false;
  Timer? _measureTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrolled);
    widget.openTask?.addListener(_onOpenTask);
    // Measuring waits until the board has faded in (see _measureDelay).
    _measureTimer = Timer(_measureDelay, () {
      if (mounted) setState(() {});
    });
    // A task opened before this column was built (switching projects: a
    // big project's board comes a frame after the task opens): its card
    // is revealed once the column's laid out.
    if (widget.openTask?.value != null) _onOpenTask();
  }

  /// Waits for the form to finish sliding in before scrolling: both at
  /// once was choppy.
  Timer? _revealTimer;

  /// How long the form takes to open, and a little more.
  static const _afterFormOpens = Duration(milliseconds: 260);

  void _onOpenTask() {
    _revealTimer?.cancel();
    final id = widget.openTask?.value;
    if (id == null || !widget.tasks.any((t) => t.id == id)) return;
    _revealTimer = Timer(_afterFormOpens, () {
      if (mounted && widget.openTask?.value == id) _reveal();
    });
  }

  /// Tries again next frame, a few times, while the column isn't laid
  /// out yet.
  void _revealAfterLayout([int tries = 3]) {
    if (tries <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(tries - 1);
    });
  }

  @override
  void didUpdateWidget(_CardList old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_scrolled);
      widget.controller.addListener(_scrolled);
    }
    if (old.openTask != widget.openTask) {
      old.openTask?.removeListener(_onOpenTask);
      widget.openTask?.addListener(_onOpenTask);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrolled);
    widget.openTask?.removeListener(_onOpenTask);
    _revealTimer?.cancel();
    _measureTimer?.cancel();
    super.dispose();
  }

  /// Room left above or below a card scrolled into view.
  static const _revealMargin = 24.0;

  /// The open task's card, when it's in this column: the board scrolls
  /// sideways to the column if it's off screen, and the column to the
  /// card. Cards out of view aren't built, but every one's place is known
  /// (its last height), so it's worked out from those.
  void _reveal([int tries = 3]) {
    final id = widget.openTask?.value;
    if (id == null) return;
    final index = widget.tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final p = _position;
    if (p == null || !p.hasViewportDimension) {
      _revealAfterLayout(tries);
      return;
    }
    var top = 0.0;
    for (final t in widget.tasks.take(index)) {
      top += _cardHeights[t.id] ?? _guessedHeight;
    }
    final bottom = top + (_cardHeights[id] ?? _guessedHeight);
    final height = p.viewportDimension;
    // Already in view (a card clicked on): stays put.
    final target = top < p.pixels
        ? top - _revealMargin
        : bottom > p.pixels + height - bottomFadeHeight
        ? bottom - height + bottomFadeHeight + _revealMargin
        : null;
    const duration = Duration(milliseconds: 300);
    if (target != null) {
      final to = target.clamp(p.minScrollExtent, p.maxScrollExtent);
      // A long way off: straight to half a screen short of it, then the
      // rest smoothly. Scrolling past every card in between built each
      // screenful of them on the way, which stuttered.
      final near = height / 2;
      if ((to - p.pixels).abs() > near) {
        p.jumpTo(to > p.pixels ? to - near : to + near);
      }
      p.animateTo(to, duration: duration, curve: Curves.easeOutCubic);
    }
    // The board sideways, to the column, if it's off either edge.
    final scrollable = Scrollable.maybeOf(context, axis: Axis.horizontal);
    final view = scrollable?.context.findRenderObject();
    final column = context.findRenderObject();
    if (scrollable == null || view is! RenderBox || column is! RenderBox) {
      return;
    }
    final board = scrollable.position;
    final left = column.localToGlobal(Offset.zero).dx;
    final right = left + column.size.width;
    final viewLeft = view.localToGlobal(Offset.zero).dx;
    // Clear of the form, which slides in over the board's right side
    // (unless the board's too narrow beside it).
    final viewRight = math.max(
      viewLeft + column.size.width + _revealMargin * 2,
      viewLeft + view.size.width - taskEditorWidth,
    );
    final shift = left < viewLeft
        ? left - viewLeft - _revealMargin
        : right > viewRight
        ? right - viewRight + _revealMargin
        : null;
    if (shift != null) {
      board.animateTo(
        (board.pixels + shift).clamp(
          board.minScrollExtent,
          board.maxScrollExtent,
        ),
        duration: duration,
        curve: Curves.easeInOut,
      );
    }
  }

  ScrollPosition? get _position =>
      widget.controller.hasClients ? widget.controller.position : null;

  int _bandOf(ScrollPosition p) =>
      (p.pixels / (p.viewportDimension / 2)).floor();

  void _scrolled() {
    final p = _position;
    if (p == null || !p.hasViewportDimension) return;
    if (_bandOf(p) != _band) setState(() {});
  }

  /// A card's height changed (or it was measured for the first time):
  /// once this frame is done, work out again which cards are in view.
  void _measured(String id, double height) {
    if (_cardHeights[id] == height) return;
    _cardHeights[id] = height;
    if (_remeasured) return;
    _remeasured = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _remeasured = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    final laidOut = p != null && p.hasViewportDimension;
    // In view, plus a screen above and below: built. Before the column's
    // been laid out (opening a project), just the first screen's worth.
    final screen = laidOut
        ? p.viewportDimension
        : MediaQuery.sizeOf(context).height;
    if (laidOut) _band = _bandOf(p);
    final from = laidOut ? p.pixels - screen : 0.0;
    final to = laidOut ? p.pixels + screen * 2 : screen;
    var y = 0.0;
    var batch = 0;
    // Measuring cards out of view: not while the board fades in, and a
    // few a frame for the whole board (not per column).
    final measuring = _measureTimer?.isActive != true;
    var waiting = false, starved = false;
    // Cards not built stand in as empty space: each run of them one box
    // (their heights added up), not a box each. A big column is then a
    // few dozen widgets, not thousands, so rebuilding it (every frame
    // while cards are measured after opening) stays cheap.
    final children = <Widget>[];
    var gap = 0.0;
    void endGap() {
      if (gap > 0) children.add(SizedBox(height: gap));
      gap = 0;
    }

    for (final task in widget.tasks) {
      final top = y;
      final known = _cardHeights[task.id];
      final height = known ?? _guessedHeight;
      y += height;
      final near = top + height >= from && top <= to;
      // Cards never measured are built a few per frame (measured where
      // they stand, out of view), so a big project opens straight away
      // and its height is exact a moment later.
      var measureNow = false;
      if (laidOut && known == null && !near && batch < _batchSize) {
        if (!measuring) {
          waiting = true;
        } else if (_takeMeasureBudget()) {
          measureNow = true;
          batch++;
        } else {
          starved = true;
        }
      }
      if (!near && !measureNow) {
        gap += height;
        continue;
      }
      endGap();
      children.add(
        _Measured(
          key: ValueKey(task.id),
          onHeight: (h) => _measured(task.id, h),
          // Its own layer, so a card changing (hover) repaints only it.
          child: RepaintBoundary(child: widget.slot(task)),
        ),
      );
    }
    endGap();
    // Out of this frame's measuring: again next frame.
    if (starved && !waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...children, ...widget.trailing],
    );
  }
}

/// Every card's height when it was last laid out, by task id: kept
/// across projects and columns (cards are all [_columnWidth] wide), so a
/// project opened before is the right height straight away.
final _cardHeights = <String, double>{};

/// Standing in for a card that hasn't been measured yet.
const _guessedHeight = 110.0;

/// How many unmeasured, out-of-view cards a column builds (to measure) a
/// frame, at most.
const _batchSize = 4;

/// How many a frame for the whole board: building and dropping cards to
/// measure them, four in every column at once, made each frame of the
/// board's opening take 20 to 40ms.
const _boardMeasureBudget = 4;

/// No measuring until the board has faded in (250ms) and settled.
const _measureDelay = Duration(milliseconds: 400);

/// What's left of [_boardMeasureBudget] this frame; refilled for the
/// next frame once this one's done.
int _measureBudgetLeft = 0;
bool _measureBudgetTaken = false;

/// Takes one card from this frame's measuring budget; false when spent.
bool _takeMeasureBudget() {
  if (!_measureBudgetTaken) {
    _measureBudgetTaken = true;
    _measureBudgetLeft = _boardMeasureBudget;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => _measureBudgetTaken = false,
    );
  }
  if (_measureBudgetLeft <= 0) return false;
  _measureBudgetLeft--;
  return true;
}

/// Reports its child's height each time it's laid out.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({super.key, required this.onHeight, super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured r) =>
      r.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);
  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
