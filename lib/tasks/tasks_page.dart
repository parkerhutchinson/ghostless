import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../projects/project_dashboard.dart';
import '../projects/project_logo.dart';
import '../projects/project_repository.dart';
import '../widgets/bottom_fade.dart';
import '../widgets/frosted_bar.dart';
import '../widgets/undo_snack_bar.dart';
import 'task.dart';
import 'task_board.dart';
import 'task_card.dart';
import 'form_buttons.dart';
import 'task_editor.dart';
import 'task_repository.dart';
import '../app_theme.dart';
import '../widgets/sliding_toggle.dart';

enum TaskView { board, list, dashboard }

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
    this.openRequest,
    this.onTaskOpened,
    this.newTaskRequest,
    this.onNewTaskOpened,
    this.onSearch,
    this.onEditProject,
    this.view = TaskView.board,
    this.onViewChanged,
  });

  /// The view to show [projectId] in (its remembered one), and where a
  /// change of view is reported, to remember it for this project.
  final TaskView view;
  final ValueChanged<TaskView>? onViewChanged;

  final TaskRepository repo;

  /// Opens the project's dialog (the dashboard's Edit description); null
  /// for a project that can't be edited (a personal one).
  final VoidCallback? onEditProject;

  /// A task to open in the editor as soon as the page shows (e.g. one
  /// clicked in Activity or found by search); [onTaskOpened] is called
  /// once it has been. Each request has its own [serial], so the same
  /// task asked for again opens again.
  final ({String taskId, int serial})? openRequest;
  final VoidCallback? onTaskOpened;

  /// A new task to start as soon as the page shows (File › New Task);
  /// [onNewTaskOpened] is called once it has been. A new number each time.
  final int? newTaskRequest;
  final VoidCallback? onNewTaskOpened;

  /// Opens search: the magnifying glass in the header (⌘K too).
  final VoidCallback? onSearch;

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

class _TasksPageState extends State<TasksPage> with TickerProviderStateMixin {
  late TaskView _view = widget.view;
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

  /// Every task in a personal project is its owner's: no assignee shown.
  bool get _showAssignee => !(_project?.isPersonal ?? false);

  /// The task open in the form: its card or row is outlined in the
  /// accent until the form closes.
  /// (A notifier, so only the outlines redraw, not the whole board: a
  /// full rebuild of a big board made the form's animations skip.)
  final _openTask = ValueNotifier<String?>(null);

  Future<void> _open(Task task) async {
    _openTask.value = task.id;
    await showTaskEditor(
      context,
      widget.repo,
      task: task,
      projectId: widget.projectId,
      projects: widget.projects,
      projectRepo: widget.projectRepo,
      onDelete: task.originId == widget.projectId ? _delete : null,
    );
    if (_openTask.value == task.id) _openTask.value = null;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _openRequested();
    _newTaskRequested();
    _deferBoard();
  }

  @override
  void didUpdateWidget(TasksPage old) {
    super.didUpdateWidget(old);
    if (widget.openRequest != old.openRequest) {
      // Opening a task (from Activity or search) shows its project's
      // board, already set as its view.
      if (widget.openRequest != null) _view = widget.view;
      _openRequested();
    }
    if (widget.newTaskRequest != old.newTaskRequest) _newTaskRequested();
    if (widget.projectId != old.projectId) {
      // Each project opens in the view it was last left in.
      _view = widget.view;
      _deferBoard();
    }
  }

  /// A project with more tasks than this shows a spinner for a frame
  /// before its board, so the click (the sidebar's highlight, the header)
  /// shows at once instead of waiting for every card to be built.
  static const _deferAbove = 40;

  /// False while the spinner stands in for the board (see [_deferBoard]).
  bool _boardReady = true;

  /// On opening a big project: the spinner this frame, the board the next.
  void _deferBoard() {
    _boardFade.value = 0;
    final id = widget.projectId;
    if (widget.repo.inProject(id).length <= _deferAbove) {
      _boardReady = true;
      _fadeInAfterFrame(id);
      return;
    }
    _boardReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.projectId == id) {
        setState(() => _boardReady = true);
        _fadeInAfterFrame(id);
      }
    });
  }

  /// A project's tasks fade in once they're built (not with them: building
  /// a big board can take longer than the fade). Set by [_fadeTick].
  late final _boardFade = AnimationController(vsync: this, value: 1);

  late final _boardOpacity = CurvedAnimation(
    parent: _boardFade,
    curve: Curves.easeOut,
  );

  /// Starts the fade after the frame now being built (the board's).
  void _fadeInAfterFrame(String projectId) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.projectId == projectId) _startFade();
      });

  /// Drives [_boardFade] one step per frame, each at most a 60fps frame's
  /// worth: when the first frames after a switch are slow (drawing all the
  /// new cards), the fade slows down with them instead of being over
  /// before it's seen.
  late final Ticker _fadeTicker = createTicker(_fadeTick);
  Duration? _lastFadeTick;

  static const _fadeDuration = Duration(milliseconds: 250);
  static const _maxFadeStep = Duration(microseconds: 16667);

  void _startFade() {
    _lastFadeTick = null;
    _fadeTicker
      ..stop()
      ..start();
  }

  void _fadeTick(Duration elapsed) {
    final last = _lastFadeTick;
    _lastFadeTick = elapsed;
    if (last == null) return; // The first tick: no time has passed yet.
    final step = elapsed - last;
    final capped = step > _maxFadeStep ? _maxFadeStep : step;
    final value =
        _boardFade.value + capped.inMicroseconds / _fadeDuration.inMicroseconds;
    _boardFade.value = value.clamp(0.0, 1.0);
    if (value >= 1) _fadeTicker.stop();
  }

  /// Board ⇄ list (once the toggle has slid): the other fades in once
  /// built, as on switching projects.
  void _switchView(TaskView view) {
    _fadeTicker.stop();
    _boardFade.value = 0;
    setState(() => _view = view);
    widget.onViewChanged?.call(view);
    _fadeInAfterFrame(widget.projectId);
  }

  /// Starts [TasksPage.newTaskRequest]'s new task, after this frame.
  void _newTaskRequested() {
    final request = widget.newTaskRequest;
    if (request == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.newTaskRequest != request) return;
      widget.onNewTaskOpened?.call();
      _create();
    });
  }

  /// Opens [TasksPage.openRequest]'s task, after this frame (once the page
  /// is up).
  void _openRequested() {
    final request = widget.openRequest;
    if (request == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.openRequest != request) return;
      widget.onTaskOpened?.call();
      if (widget.repo.get(request.taskId) case final task?) _open(task);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _openTask.dispose();
    _fadeTicker.dispose();
    _boardOpacity.dispose();
    _boardFade.dispose();
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
    projectRepo: widget.projectRepo,
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
              style: deleteButtonStyle(),
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
      showAssignee: _showAssignee,
      onDuplicate: () => _duplicate(task),
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
        showAssignee: _showAssignee,
      );
    }
    return OpenOutline(
      key: ValueKey(task.id),
      openTask: _openTask,
      taskId: task.id,
      child: TaskCard(
        task: task,
        repo: widget.repo,
        multiHomes: multiHomes,
        onOpen: () => _open(task),
        completed: task.isCompletedIn(widget.projectId),
        onToggleCompleted: () =>
            widget.repo.toggleCompleted(task.id, projectId: widget.projectId),
        onToggleSubtask: (id) => widget.repo.toggleSubtask(task.id, id),
        onAssign: (id) => widget.repo.assign(task.id, id),
        showAssignee: _showAssignee,
        subtasksExpanded: expanded,
        onToggleSubtasks: () => setState(
          () => expanded ? _expandedCards.remove(key) : _expandedCards.add(key),
        ),
        onDuplicate: () => _duplicate(task),
        onDelete: isOrigin ? () => _delete(task) : null,
        onRemoveFromProject: isOrigin ? null : () => _removeFromProject(task),
      ),
    );
  }

  /// Copies [task] just below it, on every board it's on (like the task
  /// form's Duplicate), with Undo.
  Future<void> _duplicate(Task task) async {
    final copy = await widget.repo.duplicate(task.id);
    if (copy == null || !mounted) return;
    showUndoSnackBar(
      context,
      'Duplicated "${task.title}"',
      onUndo: () => widget.repo.delete(copy.id),
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
        task.files.forEach(repo.deleteImage);
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
            // The pane's full width, with the same side padding as the
            // board, so the title lines up with the first column.
            _Header(
              title: widget.title,
              color: _project?.color,
              ownerId: _project?.ownerId,
              logo: _project?.logo,
              view: _view,
              onViewChanged: _switchView,
              onSearch: widget.onSearch,
            ),
            Expanded(
              child: StreamBuilder<List<Task>>(
                stream: _tasks,
                initialData: widget.repo.current(),
                builder: (context, snapshot) {
                  // A big project's board comes a frame later: a
                  // spinner until then (see _deferBoard). Here, inside
                  // the builder, so the tasks stay listened to.
                  if (!_boardReady) {
                    return Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.mutedText,
                        ),
                      ),
                    );
                  }
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
                  return FadeTransition(
                    opacity: _boardOpacity,
                    // Keyed by project: another project's board or list
                    // starts fresh, scrolled to the start (not where the
                    // last one was left).
                    child: switch (_view) {
                      TaskView.dashboard when _project != null =>
                        ProjectDashboard(
                          key: ValueKey(widget.projectId),
                          project: _project!,
                          tasks: snapshot.requireData,
                          onEdit: widget.onEditProject,
                          // The rings fill in once the page has faded in.
                          entrance: _boardFade,
                          projects: widget.projects,
                        ),
                      TaskView.board || TaskView.dashboard => TaskBoard(
                        key: ValueKey(widget.projectId),
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
                        key: ValueKey(widget.projectId),
                        tasks: tasks,
                        openTask: _openTask,
                        showAssignee: _showAssignee,
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
                    },
                  );
                },
              ),
            ),
          ],
        ),
        // Not on the dashboard, which shows no tasks to add to.
        if (_view != TaskView.dashboard || _project == null)
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
    this.color,
    this.ownerId,
    this.logo,
    required this.view,
    required this.onViewChanged,
    this.onSearch,
  });

  final String title;

  /// The magnifying glass, right of the view toggle.
  final VoidCallback? onSearch;

  /// The project's color, shown as a dot before the title (none on pages
  /// that aren't one project).
  final Color? color;

  /// A personal project's owner: their avatar replaces the color dot.
  final String? ownerId;

  /// The project's logo, shown in place of the color dot.
  final ProjectLogo? logo;
  final TaskView view;
  final ValueChanged<TaskView> onViewChanged;

  /// The owner's avatar on a personal project, else the project's color
  /// dot; nothing on pages that aren't one project.
  Widget? _leading(BuildContext context) {
    final scope = ProfilesScope.maybeOf(context);
    if (scope?.find(ownerId) case final owner?) {
      return ProfileAvatar(
        profile: owner,
        image: scope!.imageOf(owner),
        size: 28,
      );
    }
    if (color case final color?) {
      return ProjectIcon.of(color: color, logo: logo, size: 28);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // On frosted glass across the pane, so the title reads over a
    // background image.
    return FrostedBar(
      child: Row(
        spacing: 12,
        children: [
          ?_leading(context),
          // Takes all the free space, so the view toggle sits at the far right.
          Expanded(
            // Centering the text's line box centers capitals, but the
            // lowercase letters sit about 2px below the middle at this
            // size; lifted 1px, halfway between, to look centered.
            child: Transform.translate(
              offset: const Offset(0, -1),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Always white, whatever the theme (even a light one).
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SlidingToggle<TaskView>(
            segments: const [
              ToggleSegment(
                value: TaskView.board,
                icon: Symbols.view_week,
                label: 'Board',
              ),
              ToggleSegment(
                value: TaskView.list,
                icon: Symbols.view_agenda,
                label: 'List',
              ),
              ToggleSegment(
                value: TaskView.dashboard,
                icon: Symbols.space_dashboard,
                label: 'Dash',
              ),
            ],
            selected: view,
            onChanged: onViewChanged,
          ),
          // Search: a square the toggle's height, in its style (border,
          // the background color).
          if (onSearch case final search?)
            IconButton(
              tooltip: 'Search  ⌘K',
              onPressed: search,
              iconSize: 18,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(32),
                minimumSize: const Size.square(32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: context.colors.surface,
                side: BorderSide(color: context.colors.cardBorder),
                shape: formShape,
              ),
              icon: Icon(Symbols.search, color: context.colors.text),
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
    super.key,
    required this.tasks,
    required this.openTask,
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
    this.showAssignee = true,
  });

  /// The project shown (row expansion is kept per project).
  final String projectId;

  /// The header has an Assignee column (not on a personal project).
  final bool showAssignee;

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

  /// The task open in the form: its row is outlined in the accent.
  final ValueListenable<String?> openTask;

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

  /// The list's scroll, for its scrollbar (outside the fade).
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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

  /// Sections collapsed into their heading (rows hidden), per project.
  final _collapsed = <(String projectId, String columnId)>{};

  void _toggleCollapsed(String columnId) => setState(() {
    final key = (widget.projectId, columnId);
    if (!_collapsed.remove(key)) _collapsed.add(key);
  });

  /// The section a dragged section is over (its id): its slices draw one
  /// highlight around it.
  String? _sectionHover;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
    // Every section's heading, rows (or "No tasks") as separate items, so
    // the list only builds what's on screen, and its items are all about
    // a row's height: the scrollbar's estimate of the whole list barely
    // changes as it scrolls (whole sections as items made it jump).
    final items = <_ListItem>[];
    for (final (i, column) in widget.columns.indexed) {
      final group = tasks.where((t) => t.status == column.id).toList();
      items.add(_ListItem(i, column, group, null));
      // Collapsed: just the heading.
      if (_collapsed.contains((widget.projectId, column.id))) continue;
      if (group.isEmpty) {
        items.add(_ListItem(i, column, group, -1));
      } else {
        for (var j = 0; j < group.length; j++) {
          items.add(_ListItem(i, column, group, j));
        }
      }
    }
    final keys = {for (final (k, item) in items.indexed) item.key: k};
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
                children: [
                  TaskTable.header(context, showAssignee: widget.showAssignee),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                // Fades out at the window's bottom while there's more below,
                // like a full board column.
                // The scrollbar outside the fade, so it doesn't fade too
                // (the list's own is turned off).
                builder: (context, constraints) => ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: Scrollbar(
                    controller: _scroll,
                    child: BottomFade(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          fabClearance,
                        ),
                        itemCount: items.length + 1,
                        // Rows keep their state (hover, open menus) as items
                        // around them come and go.
                        findChildIndexCallback: (key) => keys[key],
                        itemBuilder: (context, k) {
                          if (k == items.length) return _addSection(items);
                          final item = items[k];
                          return KeyedSubtree(
                            key: item.key,
                            child: _section(
                              item,
                              last:
                                  k + 1 == items.length ||
                                  items[k + 1].index != item.index,
                              child: _item(
                                context,
                                item,
                                previous: k == 0 ? null : items[k - 1],
                                rowWidth: constraints.maxWidth - 48,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "+ Add section", below the last; the space above it takes drops at
  /// the end of the last section.
  Widget _addSection(List<_ListItem> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _endTarget(items.lastOrNull, height: 16),
      AddColumnButton(
        label: 'Add section',
        width: double.infinity,
        onPressed: widget.onAddColumn,
      ),
    ],
  );

  /// The space above a section's heading: dropping a task there puts it at
  /// the end of the section before ([previous]'s), with a line to show it.
  Widget _endTarget(_ListItem? previous, {double height = 12}) {
    if (previous == null || previous.group.isEmpty) {
      return SizedBox(height: height);
    }
    final _ListItem(:column, :group) = previous;
    return DragTarget<Task>(
      onAcceptWithDetails: (d) => _drop(d.data, column, group, null),
      builder: (context, candidates, _) => SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.topCenter,
          child: candidates.isEmpty ? null : const _ListDropLine(),
        ),
      ),
    );
  }

  /// [child], one slice of [item]'s section as a target for a dragged
  /// section: hovering any slice highlights the whole section (each slice
  /// draws its part); dropped, it takes that section's place.
  Widget _section(_ListItem item, {required bool last, required Widget child}) {
    final TaskColumn(:id) = item.column;
    final first = item.isHeading;
    return DragTarget<TaskColumn>(
      onWillAcceptWithDetails: (d) {
        if (d.data.id == id) return false;
        setState(() => _sectionHover = id);
        return true;
      },
      onLeave: (_) {
        if (_sectionHover == id) setState(() => _sectionHover = null);
      },
      onAcceptWithDetails: (d) {
        setState(() => _sectionHover = null);
        widget.onMoveColumn(d.data.id, item.index);
      },
      builder: (context, _, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (_sectionHover == id)
            // A little wider than the section, into the gaps either side;
            // one outline down its slices.
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
                    borderRadius: BorderRadius.vertical(
                      top: first ? containerRadius.topLeft : Radius.zero,
                      bottom: last ? containerRadius.bottomLeft : Radius.zero,
                    ),
                    border: _sliceBorder(
                      Theme.of(context).colorScheme.primary,
                      top: first,
                      bottom: last,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One list item: a section's heading, a row, or an empty section's
  /// "No tasks". The rows of a section draw its box between them: the
  /// sides, a line above each, and the bottom under the last.
  Widget _item(
    BuildContext context,
    _ListItem item, {
    required _ListItem? previous,
    required double rowWidth,
  }) {
    final _ListItem(:index, :column, :group) = item;
    if (item.isHeading) {
      return _heading(context, index, column, group, previous, rowWidth);
    }
    final empty = item.row == -1;
    final lastRow = empty || item.row == group.length - 1;
    final line = BorderSide(color: context.colors.cardBorder);
    final box = DecoratedBox(
      // On top, so a hovered row's fill doesn't cover it.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          left: line,
          right: line,
          top: line,
          bottom: lastRow ? line : BorderSide.none,
        ),
      ),
      // The rows sit on the card shade (lighter or darker than the
      // background, like the board's cards); an empty section's "No
      // tasks" on the background color.
      child: ColoredBox(
        color: empty ? context.colors.surface : context.colors.card,
        child: empty
            ? DragTarget<Task>(
                onAcceptWithDetails: (d) => _drop(d.data, column, group, null),
                builder: (context, candidates, _) => SizedBox(
                  height: TaskTable.height,
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          'No tasks',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.colors.mutedText,
                          ),
                        ),
                      ),
                      if (candidates.isNotEmpty)
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _ListDropLine(),
                        ),
                    ],
                  ),
                ),
              )
            : _slot(context, column, group, group[item.row!], rowWidth),
      ),
    );
    if (empty) return box;
    // Open in the form: outlined in the accent, over the table's lines.
    return OpenOutline(
      openTask: widget.openTask,
      taskId: group[item.row!].id,
      child: box,
    );
  }

  /// A section's heading: its name (click to rename), count, + and ⋯,
  /// like a board column's. Drag it to move the section: dropped on
  /// another, it takes that one's place (the ones between shift up or
  /// down). The space above it takes drops at the end of the section
  /// before.
  Widget _heading(
    BuildContext context,
    int index,
    TaskColumn column,
    List<Task> group,
    _ListItem? previous,
    double rowWidth,
  ) {
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
      collapsed: _collapsed.contains((widget.projectId, column.id)),
      onToggleCollapsed: full ? () => _toggleCollapsed(column.id) : null,
    );
    const headerPadding = EdgeInsets.fromLTRB(TaskTable.cellPadding, 12, 4, 0);
    // Inside the glass: the same left and right as headerPadding.
    const glassPadding = EdgeInsets.fromLTRB(TaskTable.cellPadding, 0, 4, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _endTarget(previous),
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
            child: FrostedHeader(
              padding: glassPadding,
              child: header(full: false),
            ),
          ),
          // On glass, like the page's header, so it reads over an image.
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: FrostedHeader(padding: glassPadding, child: header()),
          ),
        ),
      ],
    );
  }

  /// One row: draggable, and a drop target that puts the dropped task just
  /// before it.
  Widget _slot(
    BuildContext context,
    TaskColumn column,
    List<Task> group,
    Task task,
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
      // The line above it is drawn by its list item (see _item).
      builder: (context, candidates, _) => Column(
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
    );
  }
}

/// One item in the list view: section [index]'s ([column], its tasks
/// [group]) heading ([row] null), one of its rows ([row] its index), or
/// "No tasks" when it has none ([row] -1).
final class _ListItem {
  const _ListItem(this.index, this.column, this.group, this.row);
  final int index;
  final TaskColumn column;
  final List<Task> group;
  final int? row;

  bool get isHeading => row == null;

  /// Stable while the list changes around it: the section's heading, or
  /// the task's row.
  Key get key => ValueKey(switch (row) {
    null => 'section:${column.id}',
    -1 => 'empty:${column.id}',
    final r => 'task:${group[r].id}',
  });
}

/// A section highlight slice's outline: always the sides; the top on its
/// first slice, the bottom on its last.
Border _sliceBorder(Color color, {required bool top, required bool bottom}) {
  final side = BorderSide(color: color);
  return Border(
    left: side,
    right: side,
    top: top ? side : BorderSide.none,
    bottom: bottom ? side : BorderSide.none,
  );
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
  Widget build(BuildContext context) => SizedBox(
    height: 2,
    // The accent (Settings), like the board's drop line.
    child: ColoredBox(color: Theme.of(context).colorScheme.primary),
  );
}

/// [child] (a task's card or row), outlined in the accent while [openTask]
/// is its task ([taskId]): the one open in the form. Only this redraws
/// when the open task changes, not [child].
class OpenOutline extends StatelessWidget {
  const OpenOutline({
    super.key,
    required this.openTask,
    required this.taskId,
    required this.child,
  });

  final ValueListenable<String?> openTask;
  final String taskId;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: openTask,
    child: child,
    // Always the same box (no border when not open), so [child] is never
    // rebuilt or remounted as the outline comes and goes.
    builder: (context, open, child) => DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: open == taskId
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: child,
    ),
  );
}
