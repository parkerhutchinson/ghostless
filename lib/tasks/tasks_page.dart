import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../widgets/bottom_fade.dart';
import '../widgets/undo_snack_bar.dart';
import 'task.dart';
import 'task_board.dart';
import 'task_card.dart';
import 'task_editor.dart';
import 'task_repository.dart';
import '../app_theme.dart';

enum TaskView { board, list }

/// Width of the list view (including its side padding).
const listMaxWidth = 1250.0;

/// Builds the card for a task, as shown in the current project. [lifted] is
/// the copy that follows the pointer while dragging (no buttons).
typedef TaskCardBuilder = Widget Function(Task task, {bool lifted});

/// Distance of the New task button from the bottom-right corner.
const fabMargin = 24.0;

/// Space to leave at the bottom of scrolling lists so the New task button
/// never covers the last card.
const fabClearance = 40.0 + fabMargin;

/// One project's tasks, as a Kanban board or a list.
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.repo,
    required this.title,
    required this.projectId,
    this.projects = const [],
    required this.projectRepo,
  });

  final TaskRepository repo;

  /// Shown in the header: the project's name.
  final String title;

  /// The project shown. New tasks are created in it.
  final String projectId;

  /// All projects, for the editor's Projects picker and the cards' "also
  /// in" labels.
  final List<Project> projects;

  /// For changing this project's columns.
  final ProjectRepository projectRepo;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  TaskView _view = TaskView.board;
  late final Stream<List<Task>> _tasks = widget.repo.watch();

  /// Cards whose subtasks are shown, per project: expanding a task on one
  /// board leaves it collapsed on the others.
  final _expandedCards = <(String projectId, String taskId)>{};

  /// A column just added, whose name opens for editing.
  String? _newColumnId;

  /// This project (its columns).
  Project? get _project =>
      widget.projects.where((p) => p.id == widget.projectId).firstOrNull;

  List<TaskColumn> get _columns => _project?.columns ?? defaultColumns;

  void _open(Task task) => showTaskEditor(
    context,
    widget.repo,
    task: task,
    projectId: widget.projectId,
    projects: widget.projects,
    onDelete: task.originId == widget.projectId ? _delete : null,
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// ⌘N anywhere in the window opens a new task, wherever focus is (the
  /// sidebar, nothing at all after a click). Not while a dialog or menu is
  /// open over the page, e.g. the task editor itself.
  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyN ||
        !keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _create();
    return true;
  }

  /// New task, in [status]'s column (the first column by default).
  void _create([String? status]) => showTaskEditor(
    context,
    widget.repo,
    status: status ?? _columns.first.id,
    projectId: widget.projectId,
    projects: widget.projects,
  );

  /// Takes the task out of this project, which it was multi-homed to. No
  /// undo offered: it can be dragged back onto this project in the sidebar.
  void _removeFromProject(Task task) =>
      widget.repo.removeFromProject(task.id, widget.projectId);

  void _addColumn([String name = 'New column']) {
    final column = widget.projectRepo.addColumn(widget.projectId, name);
    setState(() => _newColumnId = column?.id);
  }

  /// Deletes [column]; its tasks move to the bottom of the first remaining
  /// column (after confirming, if there are any). Undo puts both back.
  Future<void> _deleteColumn(TaskColumn column) async {
    final columns = _columns;
    final target = columns.firstWhere((c) => c.id != column.id);
    final count = widget.repo
        .viewsIn(widget.projectId)
        .where((t) => _project?.columnFor(t.status) == column.id)
        .length;
    if (count > 0 && !await _confirmDeleteColumn(column, target, count)) {
      return;
    }
    if (!mounted) return;
    final project = _project;
    if (project == null) return;

    final moved = widget.repo.moveColumnTasks(
      widget.projectId,
      column.id,
      target.id,
    );
    widget.projectRepo.removeColumn(widget.projectId, column.id);
    showUndoSnackBar(
      context,
      '"${column.title}" deleted',
      onUndo: () {
        widget.projectRepo.save(project);
        moved.forEach(widget.repo.save);
      },
    );
  }

  Future<bool> _confirmDeleteColumn(
    TaskColumn column,
    TaskColumn target,
    int count,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "${column.title}"?'),
          content: Text(
            'Its $count task${count == 1 ? '' : 's'} will move to '
            '"${target.title}".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete column'),
            ),
          ],
        ),
      ) ??
      false;

  /// The task as a line of the list view's table.
  Widget _row(
    Task task, {
    bool expanded = false,
    VoidCallback? onToggleExpanded,
  }) {
    final isOrigin = task.originId == widget.projectId;
    return TaskRow(
      key: ValueKey(task.id),
      task: task,
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      multiHomes: [
        for (final p in widget.projects)
          if (task.multiHomes.contains(p.id)) p,
      ],
      onOpen: () => _open(task),
      completed: task.isCompletedIn(widget.projectId),
      onToggleCompleted: () =>
          widget.repo.toggleCompleted(task.id, projectId: widget.projectId),
      onAssign: (id) => widget.repo.assign(task.id, id),
      onDelete: isOrigin ? () => _delete(task) : null,
      onRemoveFromProject: isOrigin ? null : () => _removeFromProject(task),
    );
  }

  Widget _card(Task task, {bool lifted = false}) {
    final multiHomes = [
      for (final p in widget.projects)
        if (task.multiHomes.contains(p.id)) p,
    ];
    // Shown here because it was multi-homed here: it can leave this
    // project, but can't be deleted from here (only from its origin).
    final isOrigin = task.originId == widget.projectId;
    final key = (widget.projectId, task.id);
    final expanded = _expandedCards.contains(key);
    if (lifted) {
      return TaskCard(
        task: task,
        repo: widget.repo,
        multiHomes: multiHomes,
        completed: task.isCompletedIn(widget.projectId),
        subtasksExpanded: expanded,
        lifted: true,
      );
    }
    return TaskCard(
      key: ValueKey(task.id),
      task: task,
      repo: widget.repo,
      multiHomes: multiHomes,
      onOpen: () => _open(task),
      completed: task.isCompletedIn(widget.projectId),
      onToggleCompleted: () =>
          widget.repo.toggleCompleted(task.id, projectId: widget.projectId),
      onToggleSubtask: (id) => widget.repo.toggleSubtask(task.id, id),
      onAssign: (id) => widget.repo.assign(task.id, id),
      subtasksExpanded: expanded,
      onToggleSubtasks: () => setState(
        () => expanded ? _expandedCards.remove(key) : _expandedCards.add(key),
      ),
      onDelete: isOrigin ? () => _delete(task) : null,
      onRemoveFromProject: isOrigin ? null : () => _removeFromProject(task),
    );
  }

  /// Deletes right away; the images are kept until undo is no longer offered.
  void _delete(Task shown) {
    final repo = widget.repo;
    // The stored task (every board's place), not this board's view of it,
    // so Undo puts it back everywhere as it was.
    final task = repo.get(shown.id);
    if (task == null) return;
    repo.delete(task.id, keepImages: true);
    showUndoSnackBar(
      context,
      '"${task.title}" deleted',
      onUndo: () => repo.save(task),
    ).closed.then((reason) {
      if (reason != SnackBarClosedReason.action && repo.get(task.id) == null) {
        task.images.forEach(repo.deleteImage);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Full window width, with the same side padding as the
            // board, so the title lines up with the first column.
            _Header(
              title: widget.title,
              view: _view,
              onViewChanged: (v) => setState(() => _view = v),
            ),
            Expanded(
              child: StreamBuilder<List<Task>>(
                stream: _tasks,
                initialData: widget.repo.current(),
                builder: (context, snapshot) {
                  // Each project has its own board: tasks as placed
                  // here (column and order).
                  // A status this board has no column for (deleted, or
                  // a new multi-home) shows in its first column.
                  final columns = _columns;
                  // The new column has been built (and opened for its
                  // name); don't open it again on later rebuilds.
                  if (columns.any((c) => c.id == _newColumnId)) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _newColumnId = null,
                    );
                  }
                  String columnFor(String status) =>
                      columns.any((c) => c.id == status)
                      ? status
                      : columns.first.id;
                  final tasks = [
                    for (final t in TaskRepository.viewsOf(
                      snapshot.requireData,
                      widget.projectId,
                    ))
                      t.copyWith(status: columnFor(t.status)),
                  ];
                  return switch (_view) {
                    TaskView.board => TaskBoard(
                      tasks: tasks,
                      repo: widget.repo,
                      projectId: widget.projectId,
                      card: _card,
                      onCreate: _create,
                      columns: columns,
                      onRenameColumn: (id, name) => widget.projectRepo
                          .renameColumn(widget.projectId, id, name),
                      onMoveColumn: (id, index) => widget.projectRepo
                          .moveColumn(widget.projectId, id, index),
                      onDeleteColumn: _deleteColumn,
                      onAddColumn: _addColumn,
                      editingColumnId: _newColumnId,
                    ),
                    TaskView.list => _TaskList(
                      tasks: tasks,
                      row: _row,
                      columns: columns,
                      onMove: (task, columnId, index) => widget.repo.move(
                        task.id,
                        columnId,
                        index,
                        projectId: widget.projectId,
                      ),
                      onCreate: _create,
                      onRenameColumn: (id, name) => widget.projectRepo
                          .renameColumn(widget.projectId, id, name),
                      onDeleteColumn: _deleteColumn,
                      onAddColumn: () => _addColumn('New section'),
                      onMoveColumn: (id, index) => widget.projectRepo
                          .moveColumn(widget.projectId, id, index),
                      onToggleSubtask: widget.repo.toggleSubtask,
                      onMoveSubtask: widget.repo.moveSubtask,
                      projectId: widget.projectId,
                      editingColumnId: _newColumnId,
                    ),
                  };
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: fabMargin,
          bottom: fabMargin,
          // The small size: 40px square instead of 56.
          child: FloatingActionButton.small(
            onPressed: _create,
            child: const Icon(Symbols.add),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.view,
    required this.onViewChanged,
  });

  final String title;
  final TaskView view;
  final ValueChanged<TaskView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        spacing: 12,
        children: [
          // Takes all the free space, so the view toggle sits at the far right.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
          SegmentedButton<TaskView>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              // Same border color as the task cards.
              side: BorderSide(color: context.colors.cardBorder),
            ),
            segments: const [
              ButtonSegment(
                value: TaskView.board,
                icon: Icon(Symbols.view_week, size: 18),
                label: Text('Board'),
              ),
              ButtonSegment(
                value: TaskView.list,
                icon: Icon(Symbols.view_agenda, size: 18),
                label: Text('List'),
              ),
            ],
            selected: {view},
            onSelectionChanged: (s) => onViewChanged(s.single),
          ),
        ],
      ),
    );
  }
}

/// All tasks in one scrolling list, grouped by column.
/// The list view: one header row fixed at the top, then a group per board
/// column (in board order) scrolling under it, each task one line with its
/// fields in columns (see [TaskTable]).
class _TaskList extends StatefulWidget {
  const _TaskList({
    required this.tasks,
    required this.row,
    required this.columns,
    required this.onMove,
    required this.onCreate,
    required this.onRenameColumn,
    required this.onDeleteColumn,
    required this.onAddColumn,
    required this.onMoveColumn,
    required this.onToggleSubtask,
    required this.onMoveSubtask,
    required this.projectId,
    this.editingColumnId,
  });

  /// The project shown (row expansion is kept per project).
  final String projectId;

  /// Moves a section to an index (counted without it), like dragging a
  /// column on the board.
  final void Function(String columnId, int index) onMoveColumn;

  /// The same column actions as the board's, on each section's heading.
  final ValueChanged<String> onCreate;
  final void Function(String columnId, String name) onRenameColumn;
  final ValueChanged<TaskColumn> onDeleteColumn;
  final VoidCallback onAddColumn;

  /// A section whose name opens for editing (one just added).
  final String? editingColumnId;

  /// This project's columns, in board order.
  final List<TaskColumn> columns;

  final List<Task> tasks;
  final Widget Function(
    Task task, {
    bool expanded,
    VoidCallback? onToggleExpanded,
  })
  row;

  /// Checks a task's subtask off or on: (task id, subtask id).
  final void Function(String taskId, String subtaskId) onToggleSubtask;

  /// Moves a task's subtask to an index (counted without it).
  final void Function(String taskId, String subtaskId, int index) onMoveSubtask;

  /// Moves a dragged task into a column's group at an index (counted
  /// without the task itself), like dropping a card on the board.
  final void Function(Task task, String columnId, int index) onMove;

  @override
  State<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<_TaskList> {
  /// Tasks whose subtasks are shown under their row, per project: a task
  /// in several projects is expanded in each separately. (This state
  /// stays when another project is shown, so each keeps its own.)
  final _expanded = <(String projectId, String taskId)>{};

  /// Drops [dragged] into [column]'s [group] just before [beforeId], or at
  /// the end when null.
  void _drop(
    Task dragged,
    TaskColumn column,
    List<Task> group,
    String? beforeId,
  ) {
    final others = group.where((t) => t.id != dragged.id).toList();
    final index = beforeId == null
        ? others.length
        : others.indexWhere((t) => t.id == beforeId);
    widget.onMove(dragged, column.id, index);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: listMaxWidth),
        // One header row, fixed at the top; the groups scroll under it.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [TaskTable.header(context)],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                // Fades out at the window's bottom while there's more below,
                // like a full board column.
                builder: (context, constraints) => BottomFade(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, fabClearance),
                    children: [
                      // Every column is a section, empty ones too, so each can
                      // take new tasks and drops.
                      for (final (i, column) in widget.columns.indexed)
                        _group(
                          context,
                          i,
                          column,
                          tasks.where((t) => t.status == column.id).toList(),
                          rowWidth: constraints.maxWidth - 48,
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: AddColumnButton(
                          label: 'Add section',
                          width: double.infinity,
                          onPressed: widget.onAddColumn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A column's heading and its rows in a bordered box. The whole group
  /// takes drops (at its end); each row takes drops just before it.
  ///
  /// Drag a section by its heading to move it: dropped on another section,
  /// it takes that one's place (the ones between shift up or down).
  Widget _group(
    BuildContext context,
    int index,
    TaskColumn column,
    List<Task> group, {
    required double rowWidth,
  }) {
    ColumnHeader header({bool full = true}) => ColumnHeader(
      key: full ? ValueKey(column.id) : null,
      column: column,
      count: group.length,
      noun: 'section',
      onCreate: () => widget.onCreate(column.id),
      onRename: (name) => widget.onRenameColumn(column.id, name),
      // A project always keeps one section.
      onDelete: !full || widget.columns.length < 2
          ? null
          : () => widget.onDeleteColumn(column),
      startEditing: full && column.id == widget.editingColumnId,
    );
    const headerPadding = EdgeInsets.fromLTRB(TaskTable.cellPadding, 12, 4, 0);
    return ColumnDropTarget(
      key: ValueKey(column.id),
      accepts: (c) => c.id != column.id,
      onDrop: (c) => widget.onMoveColumn(c.id, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Name (click to rename), count, + and ⋯, like a board column's.
          Draggable<TaskColumn>(
            data: column,
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: rowWidth,
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: context.colors.formBorder),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 12),
                  ],
                ),
                child: Padding(
                  padding: headerPadding,
                  child: header(full: false),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.4,
              child: Padding(
                padding: headerPadding,
                child: header(full: false),
              ),
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(padding: headerPadding, child: header()),
            ),
          ),
          DragTarget<Task>(
            onAcceptWithDetails: (d) => _drop(d.data, column, group, null),
            builder: (context, candidates, _) => DecoratedBox(
              // The group's rows in a bordered box, like the header, so the
              // column lines meet a border at each end. On top, so a hovered
              // row's fill doesn't cover it.
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.cardBorder),
              ),
              // The rows sit on the card shade (lighter or darker than the
              // background, like the board's cards); an empty section's
              // "No tasks" has none.
              child: ColoredBox(
                color: group.isEmpty ? Colors.transparent : context.colors.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, task) in group.indexed)
                      _slot(context, column, group, task, i, rowWidth),
                    // Dropping past the last row (or into an empty group).
                    if (group.isEmpty)
                      SizedBox(
                        height: TaskTable.height,
                        child: Center(
                          child: Text(
                            'No tasks',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.colors.mutedText,
                            ),
                          ),
                        ),
                      ),
                    if (candidates.isNotEmpty) const _ListDropLine(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One row: draggable, and a drop target that puts the dropped task just
  /// before it.
  Widget _slot(
    BuildContext context,
    TaskColumn column,
    List<Task> group,
    Task task,
    int i,
    double rowWidth,
  ) {
    final key = (widget.projectId, task.id);
    final expanded = _expanded.contains(key) && task.subtasks.isNotEmpty;
    final row = widget.row(
      task,
      expanded: expanded,
      onToggleExpanded: () => setState(
        () => _expanded.contains(key)
            ? _expanded.remove(key)
            : _expanded.add(key),
      ),
    );
    return DragTarget<Task>(
      key: ValueKey(task.id),
      // Takes the row itself too (dropped back in place: nothing moves),
      // so it doesn't fall through to the group and jump to the end.
      onAcceptWithDetails: (d) {
        if (d.data.id != task.id) _drop(d.data, column, group, task.id);
      },
      builder: (context, candidates, _) => DecoratedBox(
        // Each row draws the line above it on top of itself, so its hover
        // fill never covers it (a covered line would jump a pixel). Rows
        // can differ in height (wrapped tags).
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: i == 0
              ? null
              : Border(top: BorderSide(color: context.colors.cardBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Draggable<Task>(
                  data: task,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: rowWidth,
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        border: Border.all(color: context.colors.formBorder),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 12),
                        ],
                      ),
                      child: widget.row(task),
                    ),
                  ),
                  // The row's place stays, shaded, while it's dragged.
                  childWhenDragging: Stack(
                    children: [
                      row,
                      Positioned.fill(
                        child: ColoredBox(color: context.colors.emptySlot),
                      ),
                    ],
                  ),
                  child: row,
                ),
                if (candidates.any((t) => t?.id != task.id))
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _ListDropLine(),
                  ),
              ],
            ),
            if (expanded)
              _SubtaskList(
                task: task,
                onToggle: (id) => widget.onToggleSubtask(task.id, id),
                onMove: (id, index) => widget.onMoveSubtask(task.id, id, index),
              ),
          ],
        ),
      ),
    );
  }
}

/// An expanded row's subtasks, nested under it as a tree from its
/// checkbox. Drag one up or down to rearrange them (the list view is the
/// only place besides the form where they can be).
class _SubtaskList extends StatelessWidget {
  const _SubtaskList({
    required this.task,
    required this.onToggle,
    required this.onMove,
  });
  final Task task;
  final ValueChanged<String> onToggle;
  final void Function(String subtaskId, int index) onMove;

  /// The row's checkbox middle, from its left edge: the tree's trunk.
  static const _trunkX = TaskTable.cellPadding + TaskTable.checkbox / 2;

  /// Where the row's title starts: the subtasks' checkboxes line up there.
  static const _titleX =
      TaskTable.cellPadding + TaskTable.checkbox + TaskTable.titleGap;

  @override
  Widget build(BuildContext context) {
    final subtasks = task.subtasks;
    // One line across the full width above all the subtasks, separating
    // them from their task's row.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.cardBorder)),
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // The whole subtask drags (no handle), straight away with a mouse.
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        itemCount: subtasks.length,
        // `to` is already counted without the moved subtask.
        onReorderItem: (from, to) => onMove(subtasks[from].id, to),
        proxyDecorator: (child, _, _) =>
            Material(color: context.colors.card, child: child),
        itemBuilder: (context, i) {
          final sub = subtasks[i];
          return ReorderableDragStartListener(
            key: ValueKey(sub.id),
            index: i,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.only(right: TaskTable.cellPadding),
                child: SubtaskLine(
                  subtask: sub,
                  last: i == subtasks.length - 1,
                  onToggle: () => onToggle(sub.id),
                  trunkX: _trunkX,
                  branchEnd: _titleX,
                  verticalPadding: 5,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Where a dragged row will land: a line across the table.
class _ListDropLine extends StatelessWidget {
  const _ListDropLine();

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 2, child: ColoredBox(color: context.colors.text));
}
