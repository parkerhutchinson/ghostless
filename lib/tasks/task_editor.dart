import 'package:flutter/scheduler.dart';

import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/ids.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../projects/project_logo.dart';
import 'due_date_field.dart';
import 'form_buttons.dart';
import 'label_colors.dart';
import 'label_field.dart';
import 'labels_sheet.dart';
import 'project_labels.dart';
import '../comments/comments_scope.dart';
import '../comments/task_comments.dart';
import 'assignee_field.dart';
import 'attachments.dart';
import 'task.dart';
import 'task_card.dart';
import 'rich_text/rich_text_editor.dart';
import 'task_repository.dart';
import '../app_theme.dart';
import '../widgets/left_menu_button.dart';
import '../widgets/picker_dropdown.dart';
import '../widgets/undo_snack_bar.dart';
import '../widgets/selected_text.dart';
import 'image_compression.dart';
import '../reminders/reminder_service.dart';
import '../reminders/reminders.dart';
import '../files/arriving_file.dart';

/// Opens the editor for [task], or for a new task in [status] when [task]
/// is null. [projectId] is the project it's opened from: the task is always
/// in it, and the Multi-home field offers the other projects.
Future<void> showTaskEditor(
  BuildContext context,
  TaskRepository repo, {
  Task? task,
  String status = 'todo',
  required String projectId,
  List<Project> projects = const [],
  ProjectRepository? projectRepo,
  ValueChanged<Task>? onDelete,
}) => showGeneralDialog<void>(
  context: context,
  // Clicking outside the panel (or Escape) closes it without saving.
  barrierDismissible: true,
  barrierLabel: 'Close task editor',
  // The barrier only takes the click outside; the dimmed backdrop is
  // drawn by _EditorTransition, on the form's own clock.
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (_, _, _) => Align(
    alignment: Alignment.centerRight,
    child: TaskEditor(
      repo: repo,
      task: task,
      initialStatus: status,
      projectId: projectId,
      projects: projects,
      projectRepo: projectRepo,
      onDelete: onDelete,
    ),
  ),
  // Fades in while moving a little to the left into place (about 40px);
  // closing does the reverse. See _EditorTransition.
  transitionBuilder: (_, animation, _, child) =>
      _EditorTransition(route: animation, child: child),
);

/// The form's entrance and exit: faded in over 350ms while moving 60px
/// left into place, over a dimmed backdrop fading in with it; faded out
/// moving 40px back (the route's 220ms).
///
/// The entrance runs on its own clock, started once the form's first
/// frame is up: that frame (building the whole form) can take longer than
/// the animation, which would otherwise be over before anything showed.
/// Closing follows the route's animation.
class _EditorTransition extends StatefulWidget {
  const _EditorTransition({required this.route, required this.child});
  final Animation<double> route;
  final Widget child;

  @override
  State<_EditorTransition> createState() => _EditorTransitionState();
}

class _EditorTransitionState extends State<_EditorTransition>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entrance.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_entrance, widget.route]),
    builder: (context, child) {
      final closing =
          widget.route.status == AnimationStatus.reverse ||
          widget.route.status == AnimationStatus.dismissed;
      final t = closing
          ? Curves.easeInCubic.transform(widget.route.value)
          // Gentler than easeOutCubic, which covers half the way in the
          // first frame or two: the movement stays visible.
          : Curves.easeOut.transform(_entrance.value);
      return Stack(
        children: [
          // The dimmed backdrop (like Settings'), fading with the panel.
          // Clicks go through to the route's barrier, which closes it.
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.54 * t),
              ),
            ),
          ),
          Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset((1 - t) * (closing ? 40 : 60), 0),
              child: child,
            ),
          ),
        ],
      );
    },
    child: widget.child,
  );
}

/// Placeholder text color for every field in the form (30% white).

/// Space between the form's fields.
const _gap = 16.0;

/// Extra space above and below the description (on top of [_gap]), between
/// it and the card image and subtasks.
const _descriptionGap = 16.0;

/// How much less room there is above the description while it's not
/// being edited.
const _descriptionIdleLift = 30.0;

/// Width of the editor panel: room for the Project and Column pickers side
/// by side.
const taskEditorWidth = 600.0;

/// Width of the Column and Assignee pickers: the same as the due date's
/// box, so the three line up.
const _pickerWidth = dueDateFieldWidth;

/// Edits a task's title, description, column, labels and images. Changes are
/// only saved with Save; Cancel discards them (including picked images).
class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.repo,
    this.task,
    this.initialStatus = 'todo',
    required this.projectId,
    this.projects = const [],
    this.projectRepo,
    this.onDelete,
  });

  /// Where the task's labels are kept for suggesting on other tasks.
  final ProjectRepository? projectRepo;

  final TaskRepository repo;
  final Task? task;
  final String initialStatus;

  /// The project the editor was opened from. The task stays in it; the
  /// Multi-home field only lists the others.
  final String projectId;

  /// All projects; the others are offered for multi-homing.
  final List<Project> projects;

  /// Deletes the task (the caller offers undo). No Delete button when null.
  final ValueChanged<Task>? onDelete;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

/// Text size of the label and project chips, and of the Column and Due date
/// fields' values.
const _chipFontSize = formChipFontSize;
const _chipHeight = formChipHeight;
final _chipSizedButton = formButtonStyle;

/// Text size of the description and the subtasks: the same as the
/// section labels.
const _descriptionFontSize = 12.0;

class _TaskEditorState extends State<TaskEditor> {
  late final _title = AppTextController(text: widget.task?.title);

  /// Bold, italic, links and lists; saved as Markdown.
  late final _description = RichTextController.fromMarkdown(
    widget.task?.description ?? '',
  );
  final _labelInput = AppTextController();
  final _labelFocus = FocusNode();

  /// The Column picker's search field, and its box (closed on a pick).
  final _columnInput = AppTextController();
  final _columnFocus = FocusNode();
  final _columnDropdown = GlobalKey<PickerDropdownState>();
  final _projectInput = AppTextController();
  final _projectFocus = FocusNode();

  late String _status = widget.task?.status ?? widget.initialStatus;

  /// Checked off on the board the editor was opened from.
  late bool _completed = widget.task?.isCompletedIn(widget.projectId) ?? false;
  late DateTime? _dueDate = widget.task?.dueDate;

  /// The profile it's assigned to, or null for nobody.
  late String? _assigneeId = widget.task?.assigneeId;

  /// The form is scrolling (see [_onScroll]).
  bool _scrolling = false;

  /// Notes when the form's own scroll starts and stops.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && !_scrolling) {
      _setScrolling(true);
    } else if (n is ScrollEndNotification && _scrolling) {
      _setScrolling(false);
    }
    return false;
  }

  /// A scroll can end during layout (the form's content changed height):
  /// then wait for the frame to finish (setState there is an error).
  void _setScrolling(bool value) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() => _scrolling = value);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrolling != value) setState(() => _scrolling = value);
    });
  }

  late int? _dueTime = widget.task?.dueTime;

  /// Minutes before it's due to remind its assignee; null for none.
  late int? _reminder = widget.task?.reminder;

  /// The subtasks as edited (saved with Save), in order.
  late final List<Subtask> _subtasks = [...?widget.task?.subtasks];

  /// Each subtask's title field, by subtask id.
  final _subtaskTitles = <String, TextEditingController>{};
  final _subtaskInput = AppTextController();
  final _subtaskFocus = FocusNode();

  /// The subtask row under the pointer: it shows its ✕.
  /// The subtask under the pointer (its ✕ shows). A notifier, not
  /// setState: hovering (also while dragging one past the others) must not
  /// rebuild the whole form.
  final _hoveredSubtask = ValueNotifier<String?>(null);

  TextEditingController _titleOf(Subtask s) => _subtaskTitles.putIfAbsent(
    s.id,
    () => AppTextController(text: s.title)..addListener(_changed),
  );

  void _addSubtask(String text) {
    final title = text.trim();
    if (title.isEmpty) return;
    setState(() => _subtasks.add(Subtask(id: newId(), title: title)));
    _subtaskInput.clear();
    _subtaskFocus.requestFocus();
  }

  void _removeSubtask(Subtask s) {
    setState(() => _subtasks.removeWhere((x) => x.id == s.id));
    // After the frame: its field still uses the controller until then.
    final controller = _subtaskTitles.remove(s.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => controller?.dispose());
  }

  /// The subtasks to save: titles as edited, blank ones dropped, plus one
  /// typed in "Add subtask" but not yet added with Enter.
  List<Subtask> _editedSubtasks() => [
    for (final s in _subtasks)
      if (_titleOf(s).text.trim() case final t when t.isNotEmpty)
        s.copyWith(title: t),
    if (_subtaskInput.text.trim() case final t when t.isNotEmpty)
      Subtask(id: newId(), title: t),
  ];

  /// Where the task was created (a new one: the project it's created in).
  /// It always stays there, so it isn't offered in the Multi-home field.
  late final String _originId = widget.task?.originId ?? widget.projectId;

  /// Whose personal project the task belongs to; null for a shared one.
  /// A personal task is always assigned to that person.
  late final String? _personalOwner = widget.projects
      .where((p) => p.id == _originId)
      .firstOrNull
      ?.ownerId;

  /// Who it's saved as assigned to.
  String? get _assignee => _personalOwner ?? _assigneeId;

  /// The current profile: only they can set a reminder, and only on a
  /// task assigned to them. Read once (it can't change while the form is
  /// open).
  String? _me;
  bool _meRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_meRead) {
      _meRead = true;
      _me = RemindersScope.maybeOf(context)?.profiles.current?.id;
    }
  }

  bool get _canSetReminder => canSetReminder(assigneeId: _assignee, me: _me);

  /// The projects picked in the Multi-home field.
  late final Set<String> _multiHomes = {...?widget.task?.multiHomes};
  late final List<String> _labels = [...?widget.task?.tags];

  /// Colors picked for labels created here (palette index, by label
  /// lowercased); kept on the project when saved.
  final Map<String, int> _newLabelColors = {};

  /// The card image: at most one. (Tasks saved when several were allowed
  /// keep their first; the others are removed when saved.)
  late final List<String> _images = [...?widget.task?.images.take(1)];

  /// Its attachments (images and PDFs), in order.
  late final List<Attachment> _attachments = [...?widget.task?.attachments];

  /// Files (card image, attachments) copied in during this session;
  /// deleted again on cancel.
  final Set<String> _added = {};

  /// The task as last saved here: [TaskEditor.task], or the one created
  /// by the first Save. Saving keeps the form open, so later saves update
  /// it.
  late Task? _task = widget.task;

  /// Just saved: "Saved" shows by the button for a moment.
  bool _justSaved = false;
  Timer? _savedTimer;

  bool get _isNew => _task == null;

  /// Has a title, and something changed since it was opened or last
  /// saved: only then is Save lit.
  bool get _canSave => _title.text.trim().isNotEmpty && _isDirty;

  /// The form as it was last saved (or opened); see [_snapshot].
  late String _savedSnapshot;

  bool get _isDirty => _snapshot() != _savedSnapshot;

  /// Everything Save would save (and text typed but not yet added), as one
  /// comparable value.
  String _snapshot() => jsonEncode({
    'title': _title.text.trim(),
    'description': _description.toMarkdown().trim(),
    'status': _status,
    'completed': _completed,
    'dueDate': _dueDate?.toIso8601String(),
    'dueTime': _dueTime,
    'reminder': _dueDate == null ? null : _reminder,
    'assignee': _assignee,
    'multiHomes': _validMultiHomes,
    'labels': _labels,
    'labelColors': _newLabelColors,
    'labelInput': _labelInput.text.trim(),
    'images': _images,
    'attachments': [for (final a in _attachments) a.toJson()],
    'subtasks': [
      for (final s in _subtasks) [s.id, _titleOf(s).text.trim(), s.done],
    ],
    'subtaskInput': _subtaskInput.text.trim(),
  });

  void _changed() => setState(() {});

  /// Picked projects that still exist (one may have been deleted while the
  /// editor was open), in sidebar order.
  List<String> get _validMultiHomes => [
    for (final p in _otherProjects)
      if (_multiHomes.contains(p.id)) p.id,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _labelInput, _subtaskInput]) {
      c.addListener(_changed);
    }
    _savedSnapshot = _snapshot();
  }

  @override
  void dispose() {
    // Closed (the arrow, Escape, clicking outside): images picked since
    // the last save go with the unsaved edits.
    _added.forEach(widget.repo.deleteImage);
    _savedTimer?.cancel();
    _title.dispose();
    _hoveredSubtask.dispose();
    _description.dispose();
    _labelInput.dispose();
    _labelFocus.dispose();
    _columnInput.dispose();
    _columnFocus.dispose();
    _projectInput.dispose();
    _projectFocus.dispose();
    _subtaskInput.dispose();
    _subtaskFocus.dispose();
    for (final c in _subtaskTitles.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Labels already used in this task's projects (kept on the project, or
  /// on its tasks), to pick from instead of retyping. Sorted, one per
  /// spelling ignoring case.
  List<String> get _knownLabels {
    final ids = {_originId, widget.projectId};
    final byKey = <String, String>{};
    // Read fresh from the store: the projects handed in are as they were
    // when the form opened, before any labels were edited or deleted.
    final projects = [
      for (final id in ids)
        ?(widget.projectRepo?.get(id) ??
            widget.projects.where((p) => p.id == id).firstOrNull),
    ];
    for (final p in projects) {
      for (final l in p.labels) {
        byKey.putIfAbsent(l.toLowerCase(), () => l);
      }
    }
    for (final id in ids) {
      for (final t in widget.repo.inProject(id)) {
        for (final l in t.tags) {
          byKey.putIfAbsent(l.toLowerCase(), () => l);
        }
      }
    }
    return byKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Adds the comma-separated labels in [input], spelled as an existing
  /// label when one matches (ignoring case). A new one gets [color] (a
  /// palette index) when given.
  void _addLabels(String input, {int? color}) {
    final known = {for (final l in _knownLabels) l.toLowerCase(): l};
    final have = {for (final l in _labels) l.toLowerCase()};
    final added = [
      for (final l in input.split(',').map(clipLabel))
        if (l.isNotEmpty && have.add(l.toLowerCase()))
          known[l.toLowerCase()] ?? l,
    ];
    // A label from the project it's opened from (multi-homed) that the
    // origin has no color for yet: it brings its color along, so it's
    // the same in both.
    final origin = widget.projectRepo?.get(_originId)?.labelColors ?? {};
    final here = widget.projectId == _originId
        ? const <String, int>{}
        : widget.projectRepo?.get(widget.projectId)?.labelColors ?? {};
    setState(() {
      _labels.addAll(added);
      for (final l in added) {
        final key = l.toLowerCase();
        if (!known.containsKey(key)) {
          if (color != null) _newLabelColors[key] = color;
        } else if (!origin.containsKey(key) && here[key] != null) {
          _newLabelColors[key] = here[key]!;
        }
      }
    });
    _labelInput.clear();
    _labelFocus.requestFocus();
  }

  /// Picks the card image, replacing the current one.
  Future<void> _pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    if (file == null) return;
    final name = await widget.repo.addImage(file.path);
    if (!mounted) return widget.repo.deleteImage(name);
    setState(() {
      _images
        ..clear()
        ..add(name);
      _added.add(name);
    });
  }

  /// Picks files to attach (images and PDFs), added after the others.
  Future<void> _pickAttachments() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images and PDFs',
          extensions: Attachment.extensions,
          uniformTypeIdentifiers: ['public.image', 'com.adobe.pdf'],
        ),
      ],
    );
    final added = [
      for (final f in files)
        if (await widget.repo.addImage(f.path) case final stored)
          // Named for what it's kept as (a PNG photo kept as JPEG).
          Attachment(file: stored, name: withExtensionOf(f.name, stored)),
    ];
    if (!mounted) {
      for (final a in added) {
        widget.repo.deleteImage(a.file);
      }
      return;
    }
    setState(() {
      _attachments.addAll(added);
      _added.addAll([for (final a in added) a.file]);
    });
  }

  /// Removing attachments: each tile shows a ✕ (toggled by the ✎ by the
  /// Attachments heading).
  bool _editingAttachments = false;

  /// The ✎ by the Attachments heading (✓ while editing); none without
  /// attachments.
  Widget? _attachmentsButton() {
    if (_attachments.isEmpty) return null;
    return IconButton(
      tooltip: _editingAttachments ? 'Done' : 'Edit attachments',
      iconSize: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () =>
          setState(() => _editingAttachments = !_editingAttachments),
      icon: Icon(_editingAttachments ? Symbols.check : Symbols.edit),
    );
  }

  /// Files of this task still in the form (the rest can be deleted).
  Set<String> get _keptFiles => {
    ..._images,
    for (final a in _attachments) a.file,
  };

  void _save() {
    if (!_canSave) return;
    if (_labelInput.text.trim().isNotEmpty) _addLabels(_labelInput.text);
    final repo = widget.repo;
    final title = _title.text.trim();
    final description = _description.toMarkdown().trim();
    final subtasks = _editedSubtasks();
    if (_isNew) {
      final created = repo.create(
        title: title,
        description: description,
        status: _status,
        tags: _labels,
        images: _images,
        attachments: _attachments,
        originId: _originId,
        multiHomes: _validMultiHomes,
        dueDate: _dueDate,
        dueTime: _dueTime,
        subtasks: subtasks,
        assigneeId: _assignee,
        reminder: _reminder,
      );
      if (_completed) repo.save(created.withCompleted(_originId, true));
      _task = repo.get(created.id) ?? created;
    } else {
      final task = _task!;
      // Files removed in the editor are deleted only once the change is
      // saved.
      final kept = _keptFiles;
      task.files.where((f) => !kept.contains(f)).forEach(repo.deleteImage);
      repo.setMultiHomes(task.id, _validMultiHomes);
      if (_status != task.status) {
        // Bottom of the new column, on the board it was opened from only.
        repo.move(task.id, _status, 1 << 30, projectId: widget.projectId);
      }
      final moved = repo.get(task.id) ?? task;
      repo.save(
        moved
            .copyWith(
              title: title,
              description: description,
              tags: _labels,
              images: _images,
              attachments: [..._attachments],
              dueDate: _dueDate,
              dueTime: _dueDate == null ? null : _dueTime,
              subtasks: subtasks,
              assigneeId: _assignee,
              reminder: _dueDate == null ? null : _reminder,
            )
            .withCompleted(widget.projectId, _completed),
      );
      _task = repo.get(task.id) ?? _task;
    }
    // Kept on the project, to suggest on its other tasks.
    for (final id in {_originId, widget.projectId}) {
      widget.projectRepo?.addLabels(id, _labels, colors: _newLabelColors);
    }
    // Picked and then removed again before saving; the rest are saved.
    final kept = _keptFiles;
    _added.where((f) => !kept.contains(f)).forEach(repo.deleteImage);
    _added.clear();
    // Stays open: only the arrow, Escape or clicking outside closes it.
    _savedTimer?.cancel();
    setState(() {
      _justSaved = true;
      _savedSnapshot = _snapshot();
    });
    _savedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justSaved = false);
    });
  }

  /// Copies the task as saved (not the edits here, which stay open to
  /// save), just below it; Undo deletes the copy.
  Future<void> _duplicate() async {
    final copy = await widget.repo.duplicate(_task!.id);
    if (copy == null || !mounted) return;
    showUndoSnackBar(
      context,
      'Duplicated "${_task!.title}"',
      onUndo: () => widget.repo.delete(copy.id),
    );
  }

  /// The ⋯ menu: Duplicate, and Delete (only in the task's own project).
  /// A new task has nothing to duplicate or delete yet.
  Widget _menu() {
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
      tooltip: 'Task options',
      iconSize: 18,
      // A square the height of Mark complete, like the close arrow.
      buttonSize: _chipHeight,
      icon: Icon(Symbols.more_horiz),
      onSelected: (action) => action(),
      constraints: const BoxConstraints(minWidth: 180),
      itemBuilder: (_) => [
        item('Duplicate', Symbols.content_copy, _isNew ? null : _duplicate),
        if (widget.onDelete != null)
          item(
            'Delete',
            null,
            _isNew ? null : _delete,
            color: Colors.red.shade300,
          ),
      ],
    );
  }

  /// Closes without saving edits, then deletes the task as it was saved.
  void _delete() {
    Navigator.pop(context);
    widget.onDelete!(widget.repo.get(_task!.id) ?? _task!);
  }

  @override
  Widget build(BuildContext context) {
    final editing = _editingLabels;
    // Always a Stack, so opening the labels doesn't rebuild the form (and
    // lose its scroll position). They open over the form only, not the
    // rest of the app.
    return SizedBox(
      width: taskEditorWidth,
      child: Stack(
        children: [
          _panel(),
          if (editing != null)
            Positioned.fill(
              child: LabelsSheet(
                labels: editing,
                changes: _labelChanges,
                projectName:
                    widget.projects
                        .where((p) => p.id == _originId)
                        .firstOrNull
                        ?.name ??
                    'this project',
                onClose: _closeLabels,
              ),
            ),
        ],
      ),
    );
  }

  // A full-height panel on the right, over the dimmed backdrop: no
  // shadow, no edge line.
  Widget _panel() {
    return Material(
      color: context.colors.surface,
      // No edge line: the dimmed backdrop sets it off from the app.
      child: SizedBox(
        width: taskEditorWidth,
        height: double.infinity,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Mark complete, and the reminder button and ⋯ menu in the top-right
              // corner, with a line below separating it from the form. Same
              // space above and below the button.
              Container(
                // The same space above and below as the footer.
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.colors.formBorder),
                  ),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    _completeButton(),
                    const Spacer(),
                    // Only on tasks assigned to you: a reminder goes to
                    // the assignee, so only they set one.
                    if (_canSetReminder) _reminderButton(),
                    _menu(),
                  ],
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: SingleChildScrollView(
                    // Extra room at the bottom, so the last field can scroll up clear
                    // of the window edge.
                    padding: const EdgeInsets.fromLTRB(24, _gap, 24, 120),
                    // No hover or clicks while the form scrolls, so fields and
                    // buttons under the pointer don't react (or grab the swipe).
                    child: IgnorePointer(
                      ignoring: _scrolling,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: _gap,
                        children: [
                          // A little extra room (8px) between the title and the
                          // fields below it.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              // Never scrolls (or bounces) on its own: a swipe over it
                              // scrolls the form instead.
                              scrollPhysics:
                                  const NeverScrollableScrollPhysics(),
                              controller: _title,
                              autofocus: _isNew,
                              // Long titles wrap and the field grows; Enter still
                              // saves instead of adding a line break.
                              minLines: 1,
                              maxLines: null,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(
                                  RegExp(r'[\r\n]+'),
                                  replacementString: ' ',
                                ),
                              ],
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w400,
                              ),
                              decoration: InputDecoration(
                                // No inner padding, so the gap above the title is
                                // exactly _gap.
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Task title',
                                hintStyle: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w400,
                                  color: context.colors.placeholder,
                                ),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _save(),
                            ),
                          ),
                          _inline(
                            'Due date',
                            DueDateField(
                              date: _dueDate,
                              time: _dueTime,
                              onChanged: (date, time) => setState(() {
                                _dueDate = date;
                                _dueTime = time;
                              }),
                            ),
                          ),
                          if (ProfilesScope.maybeOf(context) case final scope?)
                            _inline('Assignee', _assigneePicker(scope)),
                          _inline('Column', _columnPicker()),
                          // Where it was created, when it's opened from
                          // another project it's multi-homed in.
                          if (_originProject case final origin?
                              when _originId != widget.projectId)
                            _inline(
                              'Task origin',
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _projectChip(origin),
                              ),
                            ),
                          if (_otherProjects.isNotEmpty)
                            _inline('Multi-home task', _multiHomePicker()),
                          // A little extra room (8px) before the card
                          // image.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _inline(
                              'Labels',
                              _labelEditor(),
                              action: _labelsButton(),
                              // The chips' row (or "Add label", a field's
                              // height): the label centres on it, whatever
                              // the chips' height.
                              firstLine: _labels.isEmpty
                                  ? formFieldHeight
                                  : LabelChip.largeHeight,
                            ),
                          ),
                          _section(
                            'Card image',
                            SizedBox(
                              width: double.infinity,
                              child: _imageEditor(),
                            ),
                          ),
                          // No label: the placeholder says what it's for.
                          // Set further apart from the card image above and
                          // the subtasks below than the other fields are.
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: _descriptionGap,
                            ),
                            child: RichTextEditor(
                              // 30 less room above while it's not being
                              // edited, back as its toolbar fades in.
                              idleLift: _descriptionIdleLift,
                              controller: _description,
                              // Toolbar and outline only while editing.
                              toolsWhileEditing: true,
                              // The same size as the section labels.
                              fontSize: _descriptionFontSize,
                              hintText: 'Add description',
                              // Roomier above and below than the usual 12:
                              // 18 on the Mac, whose compact density takes 4
                              // off these (and adds 4 to the sides, so they
                              // stay 16).
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 22,
                              ),
                            ),
                          ),
                          _section('Subtasks', _subtaskEditor()),
                          _section(
                            'Attachments',
                            AttachmentGrid(
                              attachments: _attachments,
                              fileOf: (a) => widget.repo.imageFile(a.file),
                              onAdd: _pickAttachments,
                              editing: _editingAttachments,
                              onRemove: (a) => setState(() {
                                _attachments.remove(a);
                                // Nothing left to edit.
                                if (_attachments.isEmpty) {
                                  _editingAttachments = false;
                                }
                              }),
                            ),
                            action: _attachmentsButton(),
                          ),
                          if (CommentsScope.maybeOf(context) != null)
                            // Set apart from the task's own fields above by
                            // a line across the whole form (like the
                            // footer's), with room either side.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // With the form's gap before it: 24 above.
                                const SizedBox(height: _gap / 2),
                                const _FullWidthLine(sidePadding: 24),
                                const SizedBox(height: 24),
                                _section(
                                  'Comments',
                                  TaskComments(
                                    // A new task gets comments once created.
                                    taskId: _task?.id,
                                    fontSize: _descriptionFontSize,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Footer: the actions, with a line above separating them from
              // the form.
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.colors.formBorder),
                  ),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    // Closes, dropping unsaved edits (like Escape or
                    // clicking outside). Save doesn't close.
                    FormCloseButton(onPressed: () => Navigator.pop(context)),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: _justSaved ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Row(
                        spacing: 4,
                        children: [
                          Icon(
                            Symbols.check,
                            size: 16,
                            color: context.colors.mutedText,
                          ),
                          Text(
                            'Saved',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.colors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: _chipSizedButton,
                      onPressed: _canSave ? _save : null,
                      child: Text(_isNew ? 'Create task' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// The space between an inline field's label and the field.
  static const _inlineGap = 80.0;

  /// How wide the inline labels' column is: the widest of them (with the
  /// Labels pencil), so every field starts at the same place.
  double _inlineLabelWidth(BuildContext context) {
    final labels = [
      'Column',
      'Assignee',
      'Due date',
      'Task origin',
      'Multi-home task',
    ];
    double width(String text) {
      final painter = TextPainter(
        // In the app's font, as the label is drawn.
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(_labelStyle),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    var widest = width('Labels') + 4 + 24;
    for (final l in labels) {
      final w = width(l);
      if (w > widest) widest = w;
    }
    return widest.ceilToDouble();
  }

  /// A field with its label on its left, centred on the field's first
  /// line, [firstLine] tall ([formFieldHeight] unless the field's first
  /// line is shorter, like the label chips), so the label stays put when
  /// chips wrap onto more lines; every inline field starts the same
  /// distance in, [_inlineGap] after the widest label.
  Widget _inline(
    String label,
    Widget child, {
    Widget? action,
    double firstLine = formFieldHeight,
  }) {
    final heading = Text(
      label,
      style: _labelStyle.copyWith(color: context.colors.text),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Measured where the label is drawn, in the form's font (the
        // state's own context is above the form's text style).
        Builder(
          builder: (context) => SizedBox(
            width: _inlineLabelWidth(context),
            height: firstLine,
            child: Row(
              spacing: 4,
              children: [
                heading,
                if (action != null)
                  SizedBox(
                    width: 24,
                    child: OverflowBox(maxHeight: 24, child: action),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: _inlineGap),
        // Loose, so a field with its own width (the pickers, the date)
        // keeps it instead of stretching across.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _section(String label, Widget child, {Widget? action}) {
    final heading = Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: context.colors.text,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        if (action == null)
          heading
        else
          // The action sits just after the heading, without making the
          // heading row taller than the others.
          SizedBox(
            height: 16,
            child: Row(
              spacing: 4,
              children: [
                heading,
                SizedBox(
                  width: 24,
                  child: OverflowBox(maxHeight: 24, child: action),
                ),
              ],
            ),
          ),
        child,
      ],
    );
  }

  /// The pencil by the Labels heading (once the task has labels): opens
  /// the project's labels, over the form.
  Widget? _labelsButton() {
    final projectRepo = widget.projectRepo;
    if (_labels.isEmpty || projectRepo == null) return null;
    return IconButton(
      tooltip: 'Edit labels',
      iconSize: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => _openLabels(projectRepo),
      icon: Icon(Symbols.edit),
    );
  }

  /// The project's labels being edited over the form; null when closed.
  ProjectLabels? _editingLabels;
  LabelChanges _labelChanges = LabelChanges();

  void _openLabels(ProjectRepository projectRepo) {
    // Labels picked here but not saved yet are on the project too, so
    // they can be edited.
    projectRepo.addLabels(_originId, _labels, colors: _newLabelColors);
    setState(() {
      _labelChanges = LabelChanges();
      _editingLabels = ProjectLabels(projectRepo, widget.repo, _originId);
    });
  }

  /// Closes the labels; the form's own labels follow what changed
  /// (without counting as an unsaved change: the task was saved with it).
  void _closeLabels() {
    final changes = _labelChanges;
    final wasDirty = _isDirty;
    setState(() {
      _editingLabels = null;
      if (changes.isEmpty) return;
      final updated = changes.applyTo(_labels);
      _labels
        ..clear()
        ..addAll(updated);
      _newLabelColors.removeWhere(
        (key, _) =>
            changes.deleted.contains(key) || changes.renamed.containsKey(key),
      );
      if (!wasDirty) _savedSnapshot = _snapshot();
    });
  }

  /// Checks the task off (or unchecks it) on this board. It doesn't change
  /// its column. Saved with Save, like every change here.
  Widget _completeButton() {
    // A new task can be checked off only once it's been created (saved).
    final toggle = _isNew
        ? null
        : () => setState(() => _completed = !_completed);
    const green = Color(0xFF34C759);
    // The same button as Save changes (the theme's filled button); green
    // once completed.
    return FilledButton(
      onPressed: toggle,
      style: _completed
          ? _chipSizedButton.merge(
              FilledButton.styleFrom(
                backgroundColor: green,
                // The near-black of the label text, not white.
                foregroundColor: labelText(green),
              ),
            )
          : _chipSizedButton,
      child: Text(_completed ? 'Completed' : 'Mark complete'),
    );
  }

  /// Every project except the task's origin.
  List<Project> get _otherProjects => [
    for (final p in widget.projects)
      if (p.id != _originId) p,
  ];

  /// The other projects, as chips. Click one to also show the task there;
  /// its ✕ takes the task back out of that project.
  /// Other projects the task isn't in yet: what "Add project" offers.
  List<Project> get _addableProjects => [
    for (final p in _otherProjects)
      if (!_multiHomes.contains(p.id)) p,
  ];

  /// The + after a row of chips: just the + until it's hovered (or
  /// focused); then the chips' background and outline. [size] is the
  /// chips' height.
  Widget _addButton(
    String tooltip,
    VoidCallback onPressed, {
    required double size,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(Symbols.add, size: size < 24 ? 14 : 16),
    style:
        IconButton.styleFrom(
          foregroundColor: context.colors.text,
          shape: formShape,
          fixedSize: Size.square(size),
          minimumSize: Size.square(size),
          padding: EdgeInsets.zero,
        ).copyWith(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => _lit(states) ? context.colors.card : Colors.transparent,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => _lit(states)
                ? BorderSide(color: context.colors.formBorder)
                : BorderSide.none,
          ),
        ),
  );

  /// A button that's hovered, focused or pressed.
  static bool _lit(Set<WidgetState> states) =>
      states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.focused) ||
      states.contains(WidgetState.pressed);

  void _addProject(Project p) {
    setState(() => _multiHomes.add(p.id));
    _projectInput.clear();
    _projectFocus.requestFocus();
  }

  /// The project the task was created in.
  Project? get _originProject =>
      widget.projects.where((p) => p.id == _originId).firstOrNull;

  /// A project as a chip, styled like the project labels on cards and
  /// list rows: its mark, white text, a plain outline. With [onDeleted],
  /// a ✕ takes it off; without, it's read-only.
  Widget _projectChip(Project p, {VoidCallback? onDeleted}) => SizedBox(
    // As tall as the form's fields.
    height: formFieldHeight,
    child: InputChip(
      // The Mac's compact density would draw it shorter than the fields.
      visualDensity: VisualDensity.standard,
      label: Text(
        p.name,
        style: TextStyle(fontSize: _chipFontSize, color: context.colors.text),
      ),
      avatar: ProjectIcon(project: p, size: 14),
      backgroundColor: context.colors.card,
      side: BorderSide(color: context.colors.formBorder),
      deleteIcon: Icon(Symbols.close, size: 14, color: context.colors.text),
      // An empty message means no tooltip on the ✕.
      deleteButtonTooltipMessage: '',
      onDeleted: onDeleted,
    ),
  );

  /// The projects the task is also in, as chips (✕ takes it back out),
  /// with a + in line after them; with none yet, "Add project". Either
  /// opens a box (like the labels') with a field at the top that narrows
  /// the projects the task isn't in yet, listed under it: click one, or
  /// ↑ ↓ then Enter (Enter alone adds the first).
  Widget _multiHomePicker() {
    final added = [
      for (final p in _otherProjects)
        if (_multiHomes.contains(p.id)) p,
    ];
    List<Project> matches(String text) =>
        projectSuggestions(_addableProjects, text);
    return PickerDropdown(
      controller: _projectInput,
      focusNode: _projectFocus,
      hint: 'Find project',
      count: (text) => matches(text).length,
      list: (context, text, highlight) {
        final options = matches(text);
        if (options.isEmpty) return null;
        return PickerList(
          itemCount: options.length,
          itemBuilder: (context, i) => PickerItem(
            active: i == highlight,
            onTap: () => _addProject(options[i]),
            child: Row(
              spacing: 8,
              children: [
                ProjectIcon(project: options[i], size: 14),
                Flexible(
                  child: Text(
                    options[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      onSubmitted: (text, highlight) {
        final options = matches(text);
        if (options.isEmpty) return;
        _addProject(options[highlight ?? 0]);
      },
      // The whole row, so the box opens under it, lined up with the chips.
      builder: (context, toggle) => Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final p in added)
            // Styled like the project labels on cards and list rows:
            // the project's dot, white text, a plain outline.
            _projectChip(
              p,
              onDeleted: () => setState(() => _multiHomes.remove(p.id)),
            ),
          if (_addableProjects.isNotEmpty)
            if (added.isEmpty)
              PickerAddText('Add project', onPressed: toggle)
            else
              // As tall as the project chips beside it.
              _addButton('Add project', toggle, size: formFieldHeight),
        ],
      ),
    );
  }

  /// The board the editor was opened from, whose columns are offered.
  List<TaskColumn> get _columns =>
      widget.projects
          .where((p) => p.id == widget.projectId)
          .firstOrNull
          ?.columns ??
      defaultColumns;

  /// The column, in a box like the due date and time fields (same
  /// outline, padding, size, a chevron on the right). Clicking it opens
  /// the same box as the other pickers: a field at the top that narrows
  /// the board's columns listed under it (the current one ticked); click
  /// one, or ↑ ↓ then Enter (Enter alone picks the first). Picking one
  /// closes it.
  Widget _columnPicker() {
    final colors = context.colors;
    // A column deleted while the editor was open falls back to the first.
    final current =
        _columns.where((c) => c.id == _status).firstOrNull ?? _columns.first;
    List<TaskColumn> matches(String text) {
      final q = text.trim().toLowerCase();
      return [
        for (final c in _columns)
          if (c.title.toLowerCase().contains(q)) c,
      ];
    }

    void pick(TaskColumn c) {
      setState(() => _status = c.id);
      _columnDropdown.currentState?.close();
    }

    final style = TextStyle(fontSize: _chipFontSize, color: colors.text);
    return PickerDropdown(
      key: _columnDropdown,
      controller: _columnInput,
      focusNode: _columnFocus,
      hint: 'Find column',
      count: (text) => matches(text).length,
      list: (context, text, highlight) {
        final options = matches(text);
        if (options.isEmpty) return null;
        return PickerList(
          itemCount: options.length,
          itemBuilder: (context, i) {
            final c = options[i];
            return PickerItem(
              active: i == highlight,
              onTap: () => pick(c),
              child: Row(
                spacing: 4,
                children: [
                  Flexible(
                    child: Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  // The current column: a ✓ (its text isn't bold).
                  if (c.id == current.id)
                    Icon(Symbols.check, size: 14, color: colors.text),
                ],
              ),
            );
          },
        );
      },
      onSubmitted: (text, highlight) {
        final options = matches(text);
        if (options.isNotEmpty) pick(options[highlight ?? 0]);
      },
      builder: (context, toggle) => SizedBox(
        width: _pickerWidth,
        child: InkWell(
          onTap: toggle,
          customBorder: formShape,
          mouseCursor: SystemMouseCursors.click,
          child: Container(
            height: formFieldHeight,
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            // The fields' outline (the due date and time boxes').
            decoration: ShapeDecoration(shape: colors.fieldBorder),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                Icon(Symbols.expand_more, size: 16, color: colors.text),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The reminder bell beside the ⋯ menu: when to remind the assignee (a macOS
  /// notification). On an accent square while one is set. Opens a
  /// menu of the choices (the one set ticked), which says why when there
  /// can't be one yet (no due date). Only shown on tasks assigned to you.
  Widget _reminderButton() {
    final hasDue = _dueDate != null;
    final current = hasDue ? _reminder : null;
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    // -1 stands for None in the menu (null means it was dismissed).
    const none = -1;
    PopupMenuEntry<int> note(String text) => PopupMenuItem<int>(
      enabled: false,
      height: 32,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: colors.mutedText),
      ),
    );
    return PopupMenuButton<int>(
      tooltip: current == null
          ? 'Add reminder'
          : 'Reminder: ${reminderLabel(current)}',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220),
      color: colors.surface,
      onSelected: (m) {
        final picked = m == none ? null : m;
        setState(() => _reminder = picked);
        // macOS asks once, the first time one is set.
        if (picked != null) {
          RemindersScope.maybeOf(context)?.requestPermission();
        }
      },
      itemBuilder: (_) => [
        note(hasDue ? 'Remind me' : 'Set a due date to add a reminder'),
        if (hasDue) ...[
          for (final m in [null, ...reminderChoices, ?_unusualReminder])
            PopupMenuItem<int>(
              value: m ?? none,
              height: 34,
              child: Row(
                spacing: 10,
                children: [
                  SizedBox(
                    width: 16,
                    child: m == current
                        ? Icon(Symbols.check, size: 16, color: colors.text)
                        : null,
                  ),
                  Text(
                    reminderLabel(m),
                    style: TextStyle(fontSize: 13, color: colors.text),
                  ),
                ],
              ),
            ),
        ],
      ],
      // A square the height of Mark complete, like the ⋯ button (the
      // theme's 4px hover square).
      iconSize: 18,
      padding: EdgeInsets.zero,
      // Set: on an accent square (the icon dark on it).
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_chipHeight),
        minimumSize: const Size.square(_chipHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: current == null ? null : accent,
      ),
      icon: Icon(
        Symbols.notifications,
        color: current == null
            ? colors.text
            : Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }

  /// A reminder not among [reminderChoices] (set by an assistant), so the
  /// menu can still show it.
  int? get _unusualReminder => switch (_reminder) {
    final m? when !reminderChoices.contains(m) => m,
    _ => null,
  };

  /// Who it's assigned to: a search field (see [AssigneeField]), as wide
  /// as the Column picker. Locked (grayed out) on a personal task: it's
  /// always its owner's.
  Widget _assigneePicker(ProfilesScope scope) {
    final locked = _personalOwner != null;
    final picker = AssigneeField(
      // A deleted profile shows as Unassigned until another is picked.
      assigneeId: scope.find(_assignee)?.id,
      fontSize: _chipFontSize,
      enabled: !locked,
      onChanged: (id) => setState(() {
        // A reminder is the assignee's own: someone new starts without.
        if (id != _assignee) _reminder = null;
        _assigneeId = id;
      }),
    );
    if (!locked) return picker;
    return Tooltip(
      message: 'Tasks in a personal project are assigned to its owner',
      child: Opacity(opacity: 0.6, child: picker),
    );
  }

  /// A label in the form: the same chip as on the cards (its padding and
  /// color), with a ✕ to take it off.
  Widget _labelChip(String label) => LabelChip(
    label,
    large: true,
    projectId: _originId,
    // A label picked here but not saved yet: the color picked for it.
    color: switch (_newLabelColors[label.toLowerCase()]) {
      final picked? => labelPalette[picked],
      null => null,
    },
    onDeleted: () => setState(() {
      _labels.remove(label);
      _newLabelColors.remove(label.toLowerCase());
    }),
  );

  /// The labels as chips, with a + in line after them (like the
  /// projects); with none yet, "Add label". Either opens a box with a field
  /// for a new label at the top and the project's labels not on the task
  /// yet under it (see [LabelField]).
  Widget _labelEditor() => LabelField(
    controller: _labelInput,
    focusNode: _labelFocus,
    projectId: _originId,
    options: (text) => labelOptions(text, known: _knownLabels, chosen: _labels),
    onAdd: _addLabels,
    // The whole row, so the box opens under it, lined up with the labels
    // (from the + it would hang off the form's edge).
    builder: (context, toggle) => Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final label in _labels) _labelChip(label),
        if (_labels.isEmpty)
          PickerAddText('Add label', onPressed: toggle)
        else
          // As tall as the label chips beside it.
          _addButton('Add label', toggle, size: LabelChip.largeHeight),
      ],
    ),
  );

  /// The subtasks, one per line: drag the handle (at the right) to
  /// rearrange them, click the circle to check one off, edit its title in
  /// place, ✕ (on hover) to remove it. "Add subtask" underneath adds one with Enter.
  Widget _subtaskEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_subtasks.isNotEmpty) _subtaskList(),
      // Flush left; once added (Enter), a subtask shows above with its
      // checkbox, its title moving over beside it.
      TextField(
        // Never scrolls (or bounces) on its own: a swipe over it
        // scrolls the form instead.
        scrollPhysics: const NeverScrollableScrollPhysics(),
        controller: _subtaskInput,
        focusNode: _subtaskFocus,
        style: const TextStyle(fontSize: _descriptionFontSize),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Add subtask, press Enter',
          hintStyle: TextStyle(
            fontSize: _descriptionFontSize,
            color: context.colors.placeholder,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onSubmitted: _addSubtask,
      ),
    ],
  );

  /// The subtasks, rearranged by dragging a handle: the others slide out
  /// of the way. The dragged one looks as it does, on the form's
  /// background, without a border.
  Widget _subtaskList() => ReorderableListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    itemCount: _subtasks.length,
    // `to` is already counted without the moved subtask.
    onReorderItem: (from, to) =>
        setState(() => _subtasks.insert(to, _subtasks.removeAt(from))),
    proxyDecorator: (child, _, _) =>
        Material(color: context.colors.surface, child: child),
    itemBuilder: (context, i) => _subtaskField(i),
  );

  /// One subtask: checkbox, title (edited in place), then ✕ (only while
  /// the pointer is over the row) and the drag handle at the right.
  Widget _subtaskField(int i) {
    final sub = _subtasks[i];
    return MouseRegion(
      key: ValueKey(sub.id),
      onEnter: (_) => _hoveredSubtask.value = sub.id,
      onExit: (_) {
        if (_hoveredSubtask.value == sub.id) _hoveredSubtask.value = null;
      },
      // Its own layer: moving it (the slide) only shifts the layer.
      child: RepaintBoundary(
        child: Row(
          spacing: 6,
          children: [
            DoneButton(
              done: sub.done,
              onPressed: () =>
                  setState(() => _subtasks[i] = sub.copyWith(done: !sub.done)),
            ),
            Expanded(
              child: TextField(
                scrollPhysics: const NeverScrollableScrollPhysics(),
                controller: _titleOf(sub),
                style: TextStyle(
                  fontSize: _descriptionFontSize,
                  color: sub.done ? context.colors.mutedText : null,
                  decoration: sub.done ? TextDecoration.lineThrough : null,
                  decorationColor: context.colors.text,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            // Its space is kept while hidden, so the title doesn't shift.
            ValueListenableBuilder(
              valueListenable: _hoveredSubtask,
              builder: (context, hovered, child) => Visibility.maintain(
                visible: hovered == sub.id,
                child: child!,
              ),
              child: IconButton(
                tooltip: 'Remove subtask',
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                onPressed: () => _removeSubtask(sub),
                icon: Icon(Symbols.close),
              ),
            ),
            ReorderableDragStartListener(
              index: i,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: SizedBox(
                  width: 20,
                  height: 34,
                  // Faint: a secondary handle, not content.
                  child: Icon(
                    Symbols.drag_indicator,
                    size: 16,
                    color: context.colors.mutedText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The card image, full width (up to 300px tall; taller images are
  /// cropped), with Replace and ✕; or an Add box when there's none.
  Widget _imageEditor() {
    final name = _images.firstOrNull;
    if (name == null) {
      return SizedBox(
        height: 96,
        // A dashed outline, like the attachments' upload tile.
        child: CustomPaint(
          foregroundPainter: DashedBorder(context.colors.formBorder),
          child: TextButton(
            onPressed: _pickImage,
            // Same faded white as the title and description placeholders,
            // not the accent color.
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: formRadius),
              padding: EdgeInsets.zero,
              foregroundColor: context.colors.placeholder,
              overlayColor: context.colors.text,
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(Symbols.add_photo_alternate),
                Text('Add card image', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    Widget overlayButton(String tooltip, IconData icon, VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: Material(
            color: context.colors.divider,
            shape: formShape,
            child: InkWell(
              customBorder: formShape,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(icon, size: 16, color: context.colors.text),
              ),
            ),
          ),
        );

    return Stack(
      children: [
        ClipRRect(
          borderRadius: formRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ArrivingFile(
              file: widget.repo.imageFile(name),
              builder: (context) => Image.file(
                widget.repo.imageFile(name),
                width: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 1200,
                // A gray box until it has loaded, so the area (and its
                // buttons) never collapses to nothing.
                frameBuilder: (_, child, frame, syncLoaded) =>
                    frame == null && !syncLoaded
                    ? Container(height: 160, color: context.colors.hover)
                    : child,
                errorBuilder: (_, _, _) => Container(
                  height: 96,
                  color: context.colors.hover,
                  child: Center(
                    child: Icon(
                      Symbols.broken_image,
                      color: context.colors.mutedText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The same border as the empty Add box, drawn over the image's edge.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: formRadius,
                border: Border.all(color: context.colors.formBorder),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            spacing: 6,
            children: [
              overlayButton('Replace image', Symbols.edit, _pickImage),
              overlayButton(
                'Remove image',
                Symbols.close,
                () => setState(() => _images.clear()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A line across the whole form, out past its content's [sidePadding] on
/// both sides to the panel's edges, in the footer line's color.
class _FullWidthLine extends StatelessWidget {
  const _FullWidthLine({required this.sidePadding});
  final double sidePadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth + sidePadding * 2;
      return SizedBox(
        height: 1,
        child: OverflowBox(
          minWidth: width,
          maxWidth: width,
          child: ColoredBox(color: context.colors.formBorder),
        ),
      );
    },
  );
}
