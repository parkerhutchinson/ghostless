import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../activity/activity.dart';
import '../activity/activity_page.dart';
import '../activity/activity_repository.dart';
import '../export/export_section.dart';
import '../mcp/mcp_service.dart';
import '../search/search_dialog.dart';
import '../sync/sync_service.dart';
import '../tasks/task.dart';
import '../tasks/task_repository.dart';
import '../layout.dart';
import '../settings/settings_dialog.dart';
import '../settings/settings_repository.dart';
import '../tasks/form_buttons.dart';
import '../tasks/tasks_page.dart';
import '../widgets/undo_snack_bar.dart';
import '../profiles/profile.dart';
import '../profiles/profile_dialog.dart';
import '../profiles/profile_repository.dart';
import 'project.dart';
import 'project_views.dart';
import 'project_dialog.dart';
import 'project_repository.dart';
import 'project_sidebar.dart';
import '../sync_status_indicator.dart';
import '../app_theme.dart';

/// Sidebar of projects next to the selected project's tasks.
class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.store,
    required this.tasks,
    required this.projects,
    required this.settings,
    required this.profiles,
    required this.activity,
    this.sync,
    this.mcp,
  });

  /// The MCP server, turned on and off in Settings.
  final McpService? mcp;

  /// The database connection, set up in Settings.
  final SyncService? sync;

  /// What others did to the current profile's tasks: the Activity view.
  final ActivityRepository activity;

  /// Whoever is using the app: their avatar opens the Profile modal; they
  /// see the shared projects plus their own personal one.
  final ProfileRepository profiles;

  /// Also keeps the selected project between launches (not synced).
  final LocalStore store;
  final TaskRepository tasks;
  final ProjectRepository projects;

  /// Opened from the Settings button at the bottom of the sidebar.
  final SettingsRepository settings;

  /// Remembered in place of a project id while the Activity view shows.
  static const activityViewId = ':activity';

  /// Project created at startup for tasks that have none.
  static const orphanProjectName = 'General';

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  static const _uiCollection = 'ui', _uiKey = 'workspace';

  late final Stream<List<Project>> _projects = widget.projects.watch();
  late final Stream<List<Task>> _tasks = widget.tasks.watch();
  late final Stream<Profile?> _profile = widget.profiles.watchCurrent();

  /// Each project's view (board, list, dashboard), remembered here.
  late final _views = ProjectViews(widget.store);

  late String? _selectedId =
      widget.store.get(_uiCollection, _uiKey)?['projectId'] as String?;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _menu.setMethodCallHandler(_onMenu);
    _adoptOrphans();
    // Image files of tasks deleted just before the app last quit.
    widget.tasks.deleteUnusedImages();
  }

  /// Every task has an origin project. Tasks whose origin is gone (saved
  /// before projects existed, or whose origin was deleted on another
  /// device) get "General" as their origin.
  void _adoptOrphans() {
    final projectIds = {for (final p in widget.projects.current()) p.id};
    final orphans = widget.tasks.orphans(projectIds);
    if (orphans.isEmpty) return;
    final home = widget.projects.create(Workspace.orphanProjectName);
    for (final t in orphans) {
      widget.tasks.adopt(t.id, home.id);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _menu.setMethodCallHandler(null);
    super.dispose();
  }

  /// ⌘K anywhere opens search; not while a dialog or menu is open over the
  /// page (search itself included).
  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _search();
    return true;
  }

  /// The macOS menu bar's choices the app handles: the app menu's
  /// Settings… (⌘,), File › New Task (⌘N), New Personal Task (⌥⌘N) and
  /// New Project (⇧⌘N), wired
  /// up in macos/Runner/AppDelegate.swift.
  static const _menu = MethodChannel('codename/menu');

  Future<void> _onMenu(MethodCall call) async {
    switch (call.method) {
      case 'openSettings':
        _openSettings();
      // New things only with nothing open over the page, like the
      // shortcuts (a task's form, a dialog).
      case 'newTask' when _pageIsFront:
        _newTask();
      case 'newPersonalTask' when _pageIsFront:
        _newPersonalTask();
      case 'newProject' when _pageIsFront:
        _create();
    }
  }

  bool get _pageIsFront => ModalRoute.of(context)?.isCurrent ?? true;

  /// A new task for the project showing ([TasksPage.newTaskRequest]); from
  /// Activity, on the project it falls back to.
  int? _newTaskRequest;
  int _newTaskSerial = 0;

  void _newTask() {
    // No project to put it in.
    final profile = widget.profiles.current?.id;
    if (visibleProjects(widget.projects.current(), profile).isEmpty) return;
    _newTaskRequest = ++_newTaskSerial;
    _select(_selectedId == Workspace.activityViewId ? null : _selectedId);
  }

  /// A new task in this profile's personal project, switching to it.
  void _newPersonalTask() {
    final profile = widget.profiles.current?.id;
    final personal = visibleProjects(
      widget.projects.current(),
      profile,
    ).where((p) => p.isPersonal).firstOrNull;
    if (personal == null) return;
    _newTaskRequest = ++_newTaskSerial;
    _select(personal.id);
  }

  /// Whether Settings is open, so the menu doesn't open a second one.
  bool _settingsOpen = false;

  /// Settings, from the sidebar's button or the app menu.
  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    try {
      await showSettingsDialog(
        context,
        widget.settings,
        sync: widget.sync,
        export: ExportSources(
          projects: widget.projects,
          tasks: widget.tasks,
          profiles: widget.profiles,
        ),
        mcp: widget.mcp,
      );
    } finally {
      _settingsOpen = false;
    }
  }

  /// Search: a found task opens on its board.
  void _search() => showSearchDialog(
    context,
    tasks: widget.tasks,
    projects: visibleProjects(
      widget.projects.current(),
      widget.profiles.current?.id,
    ),
    onOpen: _openTask,
    paneLeft: sidebarWidth,
  );

  /// A task to open once its project's board shows (from Activity or
  /// search); a new serial each time, so asking again reopens it.
  ({String taskId, int serial})? _openRequest;
  var _openSerial = 0;

  /// Goes to [projectId]'s board and opens [task] there.
  /// On the board, whatever view the project was left in: the task is
  /// opened among the others, not over a dashboard or a list.
  void _openTask(Task task, String projectId) {
    _views.set(projectId, TaskView.board);
    _openRequest = (taskId: task.id, serial: ++_openSerial);
    _select(projectId);
  }

  void _select(String? id) {
    setState(() => _selectedId = id);
    widget.store.put(_uiCollection, _uiKey, {'projectId': id});
  }

  Future<void> _create() async {
    final result = await showProjectDialog(
      context,
      defaultColorIndex: widget.projects.current().length % projectHueCount,
    );
    if (result == null) return;
    final project = widget.projects.create(
      result.name,
      colorIndex: result.colorIndex,
      logo: result.logo,
      description: result.description,
    );
    _select(project.id);
  }

  /// The project's dialog: saves its name and color, or deletes it. Not
  /// for a personal project, which has nothing to edit.
  Future<void> _edit(Project project) async {
    if (project.isPersonal) return;
    final result = await showProjectDialog(
      context,
      project: project,
      canDelete: true,
    );
    if (result == null) return;
    if (result.delete) return _delete(project);
    widget.projects.save(
      project.copyWith(
        name: result.name,
        colorIndex: result.colorIndex,
        logo: result.logo,
        description: result.description,
      ),
    );
  }

  /// Deletes the project. Tasks created in it are deleted too, wherever
  /// they're multi-homed (after confirming); tasks multi-homed to it just
  /// leave it. Undo restores everything; image files are kept until Undo is
  /// gone.
  Future<void> _delete(Project project) async {
    final repo = widget.tasks;
    final inProject = repo.inProject(project.id);
    final count = inProject.where((t) => t.originId == project.id).length;
    final shared = inProject.length - count;
    if (count > 0 && !await _confirmDelete(project, count, shared)) return;
    if (!mounted) return;

    final (:deleted, :detached) = repo.removeProject(project.id);
    widget.projects.delete(project.id);
    if (_selectedId == project.id) _select(null);
    showUndoSnackBar(
      context,
      count == 0
          ? '"${project.name}" deleted'
          : '"${project.name}" and $count task${count == 1 ? '' : 's'} deleted',
      onUndo: () {
        widget.projects.save(project);
        [...deleted, ...detached].forEach(repo.save);
        _select(project.id);
      },
    ).closed.then((reason) {
      if (reason == SnackBarClosedReason.action) return;
      for (final t in deleted.where((t) => repo.get(t.id) == null)) {
        t.images.forEach(repo.deleteImage);
      }
    });
  }

  Future<bool> _confirmDelete(Project project, int count, int shared) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.colors.surface,
          title: Text('Delete "${project.name}"?'),
          content: Text(
            [
              '${count == 1 ? 'Its 1 task' : 'Its $count tasks'} will be '
                  'deleted too.',
              if (shared > 0)
                '$shared task${shared == 1 ? '' : 's'} multi-homed here from '
                    'other projects will stay in ${shared == 1 ? 'its' : 'their'} '
                    'own project${shared == 1 ? '' : 's'}.',
            ].join(' '),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: deleteButtonStyle(),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete project'),
            ),
          ],
        ),
      ) ??
      false;

  /// Adds the dropped task to [projectId] as well. No undo offered: it can
  /// be removed from there with the card's menu.
  void _addTask(Task task, String projectId) =>
      widget.tasks.addToProject(task.id, projectId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Profile?>(
      stream: _profile,
      initialData: widget.profiles.current,
      builder: (context, profileSnap) => StreamBuilder<List<Project>>(
        stream: _projects,
        initialData: widget.projects.current(),
        builder: (context, projectSnap) =>
            _build(context, profileSnap.data, projectSnap.requireData),
      ),
    );
  }

  Widget _build(BuildContext context, Profile? profile, List<Project> all) {
    // Shared projects plus this profile's personal one (others'
    // personal projects are hidden).
    final projects = visibleProjects(all, profile?.id);
    final personal = projects.where((p) => p.isPersonal).firstOrNull;
    final shared = projects.where((p) => !p.isPersonal).toList();
    // The remembered project, or the first one if it's gone (deleted
    // here or on another device), not visible to this profile, or
    // nothing was selected yet.
    final showActivity =
        _selectedId == Workspace.activityViewId && profile != null;
    final selected =
        projects.where((p) => p.id == _selectedId).firstOrNull ??
        shared.firstOrNull ??
        personal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: sidebarWidth,
          child: StreamBuilder<List<Task>>(
            stream: _tasks,
            initialData: widget.tasks.current(),
            builder: (context, taskSnap) => StreamBuilder<List<Activity>>(
              // Keyed by profile: a switch watches the new one's activity.
              key: ValueKey(profile?.id),
              stream: profile == null
                  ? const Stream.empty()
                  : widget.activity.watch(profile.id),
              initialData: profile == null
                  ? const []
                  : widget.activity.current(profile.id),
              builder: (context, activitySnap) => ProjectSidebar(
                activitySelected: showActivity,
                unreadActivity: activitySnap.requireData
                    .where((a) => a.isUnread)
                    .length,
                onOpenActivity: () => _select(Workspace.activityViewId),
                projects: shared,
                personal: personal,
                profile:
                    profile ?? Profile(id: '', createdAt: DateTime.utc(2026)),
                profileImage: profile?.imageFile == null
                    ? null
                    : widget.profiles.imageFile(profile!.imageFile!),
                onOpenProfile: () =>
                    showProfileDialog(context, widget.profiles),
                tasks: taskSnap.requireData,
                selectedId: selected?.id,
                onSelect: _select,
                onCreate: _create,
                onEdit: _edit,
                onDropTask: _addTask,
                syncStatus: switch (widget.sync) {
                  final sync? => SyncStatusIndicator(sync: sync),
                  null => null,
                },
                onOpenSettings: _openSettings,
              ),
            ),
          ),
        ),
        Expanded(
          // From the top of the window: each page's header (FrostedBar)
          // clears the title bar strip itself.
          child: showActivity
              ? ActivityPage(
                  activity: widget.activity,
                  tasks: widget.tasks,
                  profileId: profile.id,
                  projects: projects,
                  projectRepo: widget.projects,
                  onOpenTask: _openTask,
                )
              : selected == null
              ? Padding(
                  padding: const EdgeInsets.only(top: titleBarHeight),
                  child: _NoProjects(onCreate: _create),
                )
              : TasksPage(
                  repo: widget.tasks,
                  title: selected.name,
                  projectId: selected.id,
                  projects: projects,
                  projectRepo: widget.projects,
                  openRequest: _openRequest,
                  onTaskOpened: () => _openRequest = null,
                  newTaskRequest: _newTaskRequest,
                  onNewTaskOpened: () => _newTaskRequest = null,
                  onSearch: _search,
                  view: _views.of(selected.id),
                  onViewChanged: (view) => _views.set(selected.id, view),
                  onEditProject: selected.isPersonal
                      ? null
                      : () => _edit(selected),
                ),
        ),
      ],
    );
  }
}

class _NoProjects extends StatelessWidget {
  const _NoProjects({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 14,
        children: [
          Icon(Symbols.folder, size: 40),
          const Text(
            'Tasks live in projects',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
          ),
          Text(
            'Create a project to start adding tasks.',
            style: TextStyle(color: context.colors.mutedText),
          ),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Symbols.add, size: 18),
            label: const Text('Create your first project'),
          ),
        ],
      ),
    );
  }
}
