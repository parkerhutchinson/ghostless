import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/ids.dart';
import '../profiles/profile_avatar.dart';
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
import 'attachments.dart';
import 'task.dart';
import 'task_card.dart';
import 'rich_text/rich_text_editor.dart';
import 'task_repository.dart';
import '../app_theme.dart';
import '../widgets/left_menu_button.dart';
import '../widgets/undo_snack_bar.dart';
import '../widgets/selected_text.dart';

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

/// Width of the editor panel: room for the Project and Column pickers side
/// by side.
const taskEditorWidth = 520.0;

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
      setState(() => _scrolling = true);
    } else if (n is ScrollEndNotification && _scrolling) {
      setState(() => _scrolling = false);
    }
    return false;
  }

  late int? _dueTime = widget.task?.dueTime;

  /// The subtasks as edited (saved with Save), in order.
  late final List<Subtask> _subtasks = [...?widget.task?.subtasks];

  /// Each subtask's title field, by subtask id.
  final _subtaskTitles = <String, TextEditingController>{};
  final _subtaskInput = AppTextController();
  final _subtaskFocus = FocusNode();

  /// The subtask row under the pointer: it shows its ✕.
  String? _hoveredSubtask;

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
    _description.dispose();
    _labelInput.dispose();
    _labelFocus.dispose();
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
        Attachment(file: await widget.repo.addImage(f.path), name: f.name),
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
              // Header: Mark complete, and the ⋯ menu in the top-right
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
                  children: [_completeButton(), const Spacer(), _menu()],
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
                          _section('Column', _columnPicker()),
                          if (ProfilesScope.maybeOf(context) case final scope?)
                            _section('Assignee', _assigneePicker(scope)),
                          _section(
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
                          // Where it was created, when it's opened from
                          // another project it's multi-homed in.
                          if (_originProject case final origin?
                              when _originId != widget.projectId)
                            _section(
                              'Task origin',
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _projectChip(origin),
                              ),
                            ),
                          if (_otherProjects.isNotEmpty)
                            _section('Multi-home task', _multiHomePicker()),
                          _section(
                            'Labels',
                            _labelEditor(),
                            action: _labelsButton(),
                          ),
                          _section(
                            'Card image',
                            SizedBox(
                              width: double.infinity,
                              child: _imageEditor(),
                            ),
                          ),
                          // No label: the placeholder says what it's for.
                          RichTextEditor(
                            controller: _description,
                            // The same size as the section labels.
                            fontSize: _descriptionFontSize,
                            hintText: 'Add description',
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
  Widget _projectChip(Project p, {VoidCallback? onDeleted}) => InputChip(
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
  );

  /// Like the labels: the projects the task is also in, as chips (✕ takes it
  /// back out), then an "Add project" box that suggests matching projects
  /// it isn't in yet as you type. Enter adds the highlighted one.
  Widget _multiHomePicker() {
    final addable = _addableProjects;
    final added = [
      for (final p in _otherProjects)
        if (_multiHomes.contains(p.id)) p,
    ];
    // The chips, then the field on its own line underneath.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (added.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in added)
                // Styled like the project labels on cards and list rows:
                // the project's dot, white text, a plain outline.
                _projectChip(
                  p,
                  onDeleted: () => setState(() => _multiHomes.remove(p.id)),
                ),
            ],
          ),
        if (addable.isNotEmpty)
          SizedBox(
            width: 160,
            child: RawAutocomplete<Project>(
              textEditingController: _projectInput,
              focusNode: _projectFocus,
              optionsBuilder: (value) =>
                  projectSuggestions(_addableProjects, value.text),
              displayStringForOption: (p) => p.name,
              onSelected: _addProject,
              fieldViewBuilder: (context, controller, focus, onSubmitted) =>
                  TextField(
                    // Never scrolls (or bounces) on its own: a swipe over it
                    // scrolls the form instead.
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    controller: controller,
                    focusNode: focus,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add project',
                      hintStyle: TextStyle(color: context.colors.placeholder),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => onSubmitted(),
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: context.colors.surface,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: formRadius,
                    side: BorderSide(color: context.colors.formBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      maxWidth: 220,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      children: [
                        for (final (i, p) in options.indexed)
                          InkWell(
                            onTap: () => onSelected(p),
                            child: Container(
                              color:
                                  AutocompleteHighlightedOption.of(context) == i
                                  ? context.colors.hover
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                spacing: 8,
                                children: [
                                  ProjectIcon(project: p, size: 14),
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The board the editor was opened from, whose columns are offered.
  List<TaskColumn> get _columns =>
      widget.projects
          .where((p) => p.id == widget.projectId)
          .firstOrNull
          ?.columns ??
      defaultColumns;

  /// A box like the due date and time fields: same outline, padding, size
  /// and muted icon on the right.
  Widget _columnPicker() => SizedBox(
    width: _pickerWidth,
    child: DropdownButtonFormField<String>(
      // A column deleted while the editor was open falls back to the first.
      initialValue: _columns.any((c) => c.id == _status)
          ? _status
          : _columns.first.id,
      isDense: true,
      isExpanded: true,
      borderRadius: formRadius,
      dropdownColor: context.colors.surface,
      // The same size as the label and project chips.
      style: TextStyle(fontSize: _chipFontSize, color: context.colors.text),
      icon: Icon(Symbols.expand_more, size: 16),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        enabledBorder: context.colors.fieldBorder,
        border: context.colors.fieldBorder,
      ),
      items: [
        for (final c in _columns)
          DropdownMenuItem(value: c.id, child: Text(c.title)),
      ],
      onChanged: (id) => setState(() => _status = id!),
    ),
  );

  /// Who it's assigned to: Unassigned, or any profile (avatar and name).
  /// Styled like the Column picker. Locked (grayed out) on a personal
  /// task: it's always its owner's.
  Widget _assigneePicker(ProfilesScope scope) {
    final locked = _personalOwner != null;
    final style = TextStyle(
      fontSize: _chipFontSize,
      color: context.colors.text,
    );
    // A deleted profile shows as Unassigned until another is picked.
    final current = scope.find(_assignee)?.id;
    final picker = SizedBox(
      width: _pickerWidth,
      child: DropdownButtonFormField<String?>(
        // Rebuilt when the profiles change, so the selection stays valid.
        key: ValueKey(current),
        initialValue: current,
        isDense: true,
        isExpanded: true,
        borderRadius: formRadius,
        dropdownColor: context.colors.surface,
        style: style,
        icon: Icon(Symbols.expand_more, size: 16),
        iconDisabledColor: context.colors.placeholder,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          enabledBorder: context.colors.fieldBorder,
          disabledBorder: context.colors.fieldBorder,
          border: context.colors.fieldBorder,
        ),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  Symbols.person_off,
                  size: 16,
                  color: context.colors.mutedText,
                ),
                Text(
                  'Unassigned',
                  style: style.copyWith(color: context.colors.mutedText),
                ),
              ],
            ),
          ),
          for (final p in scope.profiles)
            DropdownMenuItem<String?>(
              value: p.id,
              child: Row(
                spacing: 8,
                children: [
                  ProfileAvatar(profile: p, image: scope.imageOf(p), size: 18),
                  Flexible(
                    child: Text(p.displayName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
        onChanged: locked ? null : (id) => setState(() => _assigneeId = id),
      ),
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

  /// The labels as chips, then the field on its own line underneath (like
  /// the projects). Focused, it lists the project's labels not on the
  /// task yet (see [LabelField]).
  Widget _labelEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      if (_labels.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final label in _labels) _labelChip(label)],
        ),
      LabelField(
        controller: _labelInput,
        focusNode: _labelFocus,
        projectId: _originId,
        options: (text) =>
            labelOptions(text, known: _knownLabels, chosen: _labels),
        onAdd: _addLabels,
      ),
    ],
  );

  /// The subtasks, one per line: drag the handle (at the right) to
  /// rearrange them, click the circle to check one off, edit its title in
  /// place, ✕ (on hover) to remove it. "Add subtask" underneath adds one with Enter.
  Widget _subtaskEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_subtasks.isNotEmpty)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _subtasks.length,
          // `to` is already counted without the moved subtask.
          onReorderItem: (from, to) =>
              setState(() => _subtasks.insert(to, _subtasks.removeAt(from))),
          proxyDecorator: (child, _, _) => Material(
            color: context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: formRadius,
              side: BorderSide(color: context.colors.formBorder),
            ),
            child: child,
          ),
          itemBuilder: (context, i) => _subtaskField(i),
        ),
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

  /// One subtask: checkbox, title (edited in place), then ✕ (only while
  /// the pointer is over the row) and the drag handle at the right.
  Widget _subtaskField(int i) {
    final sub = _subtasks[i];
    final hovered = _hoveredSubtask == sub.id;
    return MouseRegion(
      key: ValueKey(sub.id),
      onEnter: (_) => setState(() => _hoveredSubtask = sub.id),
      onExit: (_) {
        if (_hoveredSubtask == sub.id) setState(() => _hoveredSubtask = null);
      },
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
          Visibility.maintain(
            visible: hovered,
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
                child: Icon(Symbols.drag_indicator, size: 16),
              ),
            ),
          ),
        ],
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
            child: Image.file(
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
