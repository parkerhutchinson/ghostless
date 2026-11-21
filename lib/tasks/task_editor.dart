import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/ids.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import 'due_date_field.dart';
import 'task.dart';
import 'task_card.dart';
import 'task_repository.dart';
import '../app_theme.dart';
import '../widgets/left_menu_button.dart';
import '../widgets/undo_snack_bar.dart';

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
  ValueChanged<Task>? onDelete,
}) => showGeneralDialog<void>(
  context: context,
  // Clicking outside the panel (or Escape) closes it without saving.
  barrierDismissible: true,
  barrierLabel: 'Close task editor',
  // No scrim: the panel sits directly on the app.
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
      onDelete: onDelete,
    ),
  ),
  // Slides in from the right edge of the window.
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    ),
    child: child,
  ),
);

/// Placeholder text color for every field in the form (30% white).

/// Space between the form's fields, and around the Mark complete button.
const _gap = 16.0;

/// Width of the editor panel: room for the Project and Column pickers side
/// by side.
const taskEditorWidth = 520.0;

/// Width of the Column and Assignee pickers, kept the same.
const _pickerWidth = 220.0;

/// Edits a task's title, description, column, tags and images. Changes are
/// only saved with Save; Cancel discards them (including picked images).
class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.repo,
    this.task,
    this.initialStatus = 'todo',
    required this.projectId,
    this.projects = const [],
    this.onDelete,
  });

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

/// Text size of the tag and project chips, and of the Column and Due date
/// fields' values.
const _chipFontSize = 12.5;

/// Text size of the description and the subtasks: the same as the
/// section labels.
const _descriptionFontSize = 12.0;

class _TaskEditorState extends State<TaskEditor> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description = TextEditingController(
    text: widget.task?.description,
  );
  final _tagInput = TextEditingController();
  final _tagFocus = FocusNode();
  final _projectInput = TextEditingController();
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
  final _subtaskInput = TextEditingController();
  final _subtaskFocus = FocusNode();

  /// The subtask row under the pointer: it shows its ✕.
  String? _hoveredSubtask;

  TextEditingController _titleOf(Subtask s) => _subtaskTitles.putIfAbsent(
    s.id,
    () => TextEditingController(text: s.title),
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

  /// The projects picked in the Multi-home field.
  late final Set<String> _multiHomes = {...?widget.task?.multiHomes};
  late final List<String> _tags = [...?widget.task?.tags];

  /// The card image: at most one. (Tasks saved when several were allowed
  /// keep their first; the others are removed when saved.)
  late final List<String> _images = [...?widget.task?.images.take(1)];

  /// Images copied in during this session; deleted again on cancel.
  final Set<String> _added = {};
  bool _saved = false;

  bool get _isNew => widget.task == null;
  bool get _canSave => _title.text.trim().isNotEmpty;

  /// Picked projects that still exist (one may have been deleted while the
  /// editor was open), in sidebar order.
  List<String> get _validMultiHomes => [
    for (final p in _otherProjects)
      if (_multiHomes.contains(p.id)) p.id,
  ];

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    // Closed without saving (Cancel, Escape, clicking outside).
    if (!_saved) _added.forEach(widget.repo.deleteImage);
    _title.dispose();
    _description.dispose();
    _tagInput.dispose();
    _tagFocus.dispose();
    _projectInput.dispose();
    _projectFocus.dispose();
    _subtaskInput.dispose();
    _subtaskFocus.dispose();
    for (final c in _subtaskTitles.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTags(String input) {
    final newTags = input
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !_tags.contains(t));
    setState(() => _tags.addAll(newTags.toSet()));
    _tagInput.clear();
    _tagFocus.requestFocus();
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

  void _save() {
    if (!_canSave) return;
    if (_tagInput.text.trim().isNotEmpty) _addTags(_tagInput.text);
    final repo = widget.repo;
    final title = _title.text.trim();
    final description = _description.text.trim();
    final subtasks = _editedSubtasks();
    if (_isNew) {
      final created = repo.create(
        title: title,
        description: description,
        status: _status,
        tags: _tags,
        images: _images,
        originId: _originId,
        multiHomes: _validMultiHomes,
        dueDate: _dueDate,
        dueTime: _dueTime,
        subtasks: subtasks,
        assigneeId: _assigneeId,
      );
      if (_completed) repo.save(created.withCompleted(_originId, true));
    } else {
      final task = widget.task!;
      // Images removed in the editor are deleted only once the change is saved.
      task.images.where((i) => !_images.contains(i)).forEach(repo.deleteImage);
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
              tags: _tags,
              images: _images,
              dueDate: _dueDate,
              dueTime: _dueDate == null ? null : _dueTime,
              subtasks: subtasks,
              assigneeId: _assigneeId,
            )
            .withCompleted(widget.projectId, _completed),
      );
    }
    // Picked and then removed again before saving.
    _added.where((i) => !_images.contains(i)).forEach(repo.deleteImage);
    _saved = true;
    Navigator.pop(context);
  }

  /// Copies the task as saved (not the edits here, which stay open to
  /// save), just below it; Undo deletes the copy.
  Future<void> _duplicate() async {
    final copy = await widget.repo.duplicate(widget.task!.id);
    if (copy == null || !mounted) return;
    showUndoSnackBar(
      context,
      'Duplicated "${widget.task!.title}"',
      onUndo: () => widget.repo.delete(copy.id),
    );
  }

  /// The ⋯ menu: Duplicate, and Delete (only in the task's own project).
  /// A new task has nothing to duplicate or delete yet.
  Widget _menu() {
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
      tooltip: 'Task options',
      iconSize: 18,
      icon: Icon(Symbols.more_horiz),
      onSelected: (action) => action(),
      constraints: const BoxConstraints(minWidth: 180),
      itemBuilder: (_) => [
        item('Duplicate', Symbols.content_copy, _isNew ? null : _duplicate),
        if (widget.onDelete != null)
          item(
            'Delete',
            Symbols.delete,
            _isNew ? null : _delete,
            color: Colors.red.shade300,
          ),
      ],
    );
  }

  /// Closes without saving edits, then deletes the task as it was saved.
  void _delete() {
    Navigator.pop(context);
    widget.onDelete!(widget.task!);
  }

  @override
  Widget build(BuildContext context) {
    return _panel();
  }

  // A full-height panel on the right: no shadow, just a left edge in the
  // same color as the form fields' outlines.
  Widget _panel() {
    return Material(
      color: context.colors.surface,
      shape: Border(left: BorderSide(color: context.colors.formBorder)),
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
                padding: const EdgeInsets.fromLTRB(24, _gap, 16, _gap),
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
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                // No inner padding, so the gap above the title is
                                // exactly _gap.
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Task title',
                                hintStyle: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
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
                          if (_otherProjects.isNotEmpty)
                            _section('Projects', _multiHomePicker()),
                          _section('Tags', _tagEditor()),
                          _section(
                            'Card image',
                            SizedBox(
                              width: double.infinity,
                              child: _imageEditor(),
                            ),
                          ),
                          _section(
                            'Description',
                            TextField(
                              // Never scrolls (or bounces) on its own: a swipe over it
                              // scrolls the form instead.
                              scrollPhysics:
                                  const NeverScrollableScrollPhysics(),
                              controller: _description,
                              // The same size as the section labels.
                              style: const TextStyle(
                                fontSize: _descriptionFontSize,
                              ),
                              // Grows with its text rather than scrolling inside.
                              minLines: 6,
                              maxLines: null,
                              decoration: InputDecoration(
                                hintText: 'Add more detail…',
                                hintStyle: TextStyle(
                                  fontSize: _descriptionFontSize,
                                  color: context.colors.placeholder,
                                ),
                                enabledBorder: context.colors.fieldBorder,
                                border: context.colors.fieldBorder,
                              ),
                            ),
                          ),
                          _section('Subtasks', _subtaskEditor()),
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
                    // Closes without saving (like Escape or clicking
                    // outside).
                    IconButton(
                      tooltip: 'Close without saving',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Symbols.arrow_back, size: 20),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: Text(_isNew ? 'Create task' : 'Save'),
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

  Widget _section(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.colors.text,
        ),
      ),
      child,
    ],
  );

  /// Checks the task off (or unchecks it) on this board. It doesn't change
  /// its column. Saved with Save, like every change here.
  Widget _completeButton() {
    // A new task can be checked off only once it's been created (saved).
    final toggle = _isNew
        ? null
        : () => setState(() => _completed = !_completed);
    const green = Color(0xFF34C759);
    // Rounded rectangle (not a pill), no icon, equal padding all round.
    const padding = EdgeInsets.all(10);
    return _completed
        ? FilledButton(
            onPressed: toggle,
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              shape: formShape,
              padding: padding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Completed'),
          )
        : OutlinedButton(
            onPressed: toggle,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.text,
              disabledForegroundColor: context.colors.placeholder,
              side: BorderSide(
                color: toggle == null
                    ? context.colors.cardBorder
                    : context.colors.formBorder,
              ),
              shape: formShape,
              padding: padding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Mark complete'),
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

  /// Like the tags: the projects the task is also in, as chips (✕ takes it
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
                InputChip(
                  label: Text(
                    p.name,
                    style: TextStyle(
                      fontSize: _chipFontSize,
                      color: context.colors.text,
                    ),
                  ),
                  avatar: Icon(Icons.circle, size: 10, color: p.color),
                  backgroundColor: context.colors.card,
                  side: BorderSide(color: context.colors.formBorder),
                  deleteIcon: Icon(
                    Symbols.close,
                    size: 14,
                    color: context.colors.text,
                  ),
                  // An empty message means no tooltip on the ✕.
                  deleteButtonTooltipMessage: '',
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
                                  Icon(Icons.circle, size: 10, color: p.color),
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
      // The same size as the tag and project chips.
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
  /// Styled like the Column picker.
  Widget _assigneePicker(ProfilesScope scope) {
    final style = TextStyle(
      fontSize: _chipFontSize,
      color: context.colors.text,
    );
    // A deleted profile shows as Unassigned until another is picked.
    final current = scope.find(_assigneeId)?.id;
    return SizedBox(
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
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          enabledBorder: context.colors.fieldBorder,
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
        onChanged: (id) => setState(() => _assigneeId = id),
      ),
    );
  }

  /// A tag in the form: the same chip (size, padding, ✕) as the projects
  /// above, in the tag's own color like on the card.
  Widget _tagChip(String tag) {
    final color = TagChip.colorFor(tag);
    final fill = Color.lerp(context.colors.card, color, 0.22)!;
    final text = context.colors.chipText(color);
    return InputChip(
      label: Text(
        tag,
        style: TextStyle(fontSize: _chipFontSize, color: text),
      ),
      backgroundColor: fill,
      // Same width border as the project chips, so they're the same size.
      side: BorderSide(color: fill),
      deleteIcon: Icon(Symbols.close, size: 14, color: text),
      deleteButtonTooltipMessage: '',
      onDeleted: () => setState(() => _tags.remove(tag)),
    );
  }

  /// The tags as chips, then the field on its own line underneath (like
  /// the projects).
  Widget _tagEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      if (_tags.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final tag in _tags) _tagChip(tag)],
        ),
      SizedBox(
        width: 160,
        child: TextField(
          // Never scrolls (or bounces) on its own: a swipe over it
          // scrolls the form instead.
          scrollPhysics: const NeverScrollableScrollPhysics(),
          controller: _tagInput,
          focusNode: _tagFocus,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Add tag, press Enter',
            hintStyle: TextStyle(color: context.colors.placeholder),
            border: InputBorder.none,
          ),
          onSubmitted: _addTags,
          onChanged: (v) {
            if (v.contains(',')) _addTags(v);
          },
        ),
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
        child: OutlinedButton(
          onPressed: _pickImage,
          // Same faded white as the title and description placeholders,
          // not the accent color.
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: formRadius),
            side: BorderSide(color: context.colors.formBorder),
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
