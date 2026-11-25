import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'activity/activity_repository.dart';
import 'app_theme.dart';
import 'data/app_data.dart';
import 'layout.dart';
import 'mcp/mcp_service.dart';
import 'mcp/mcp_tools.dart';
import 'profiles/profile_repository.dart';
import 'profiles/profiles_scope.dart';
import 'projects/project_repository.dart';
import 'projects/workspace.dart';
import 'settings/background.dart';
import 'tasks/label_colors.dart';
import 'settings/settings_repository.dart';
import 'tasks/task_repository.dart';
import 'traffic_lights.dart';
import 'comments/comment_repository.dart';
import 'comments/comments_scope.dart';

/// Shared by the window, the title bar area and the app body so they match.
const appBackground = surfaceColor;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local database first: the app works fully offline, and syncs in the
  // background when a remote is configured.
  final data = await AppData.open();

  final projects = ProjectRepository(data.store);
  // Whoever uses the app on this Mac; the first launch with profiles makes
  // one (taking over the theme picked before) along with its personal
  // project.
  final profiles = ProfileRepository(data.store, data.directory, projects)
    ..ensureProfile();
  // The theme belongs to the current profile.
  final settings = SettingsRepository(
    data.store,
    data.directory,
    profiles: profiles,
  );

  final window = WindowManager.instance.getCurrent()!;
  window.title = 'codename';
  // Hide the native title bar so the app draws behind it. The native traffic
  // lights are hidden too; TrafficLights draws custom ones (gray until hover).
  window.titleBarStyle = TitleBarStyle.hidden;
  window.isWindowControlButtonsVisible = false;
  window.backgroundColor = appBackground.toNative();
  window.setSize(const Size(1200, 800).toNative(), false);
  window.minimumSize = const Size(800, 600).toNative();
  window.center();
  window.show();

  // The native window shows through briefly while resizing; match the
  // background color.
  settings.watchBackgroundColor().listen((c) {
    window.backgroundColor = c.toNative();
  });

  // What others do to your tasks; recorded as tasks are saved here.
  final activity = ActivityRepository(
    data.store,
    actorId: () => profiles.current?.id,
  )..prune();

  // Tasks show in their board's first column when it has no column for
  // their status (deleted, or a new multi-home).
  final tasks = TaskRepository(
    data.store,
    data.directory,
    columnFor: (projectId, status) =>
        projects.get(projectId)?.columnFor(status) ?? status,
    onChange: activity.recordTaskChange,
  );

  // Comments on tasks; each one tells the task's assignee (Activity).
  final comments = CommentRepository(
    data.store,
    onAdded: (c) => activity.recordComment(tasks.get(c.taskId), c),
  );

  // Due-date reminders for whoever is using this Mac: now, then every
  // minute.
  void remind() {
    if (profiles.current?.id case final id?) {
      activity.addReminders(id, tasks.current());
    }
  }

  remind();
  Timer.periodic(const Duration(minutes: 1), (_) => remind());

  // The MCP server for AI assistants, if it was left on in Settings.
  final mcp = McpService(
    data.store,
    McpTools(
      tasks: tasks,
      projects: projects,
      profiles: profiles,
      comments: comments,
    ),
  );
  unawaited(mcp.restore());

  runApp(
    MainApp(
      data: data,
      settings: settings,
      tasks: tasks,
      projects: projects,
      profiles: profiles,
      activity: activity,
      comments: comments,
      mcp: mcp,
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({
    super.key,
    required this.data,
    required this.settings,
    required this.tasks,
    required this.projects,
    required this.profiles,
    required this.activity,
    required this.comments,
    this.mcp,
  });

  final CommentRepository comments;

  final McpService? mcp;
  final ProfileRepository profiles;
  final ActivityRepository activity;
  final AppData data;
  final SettingsRepository settings;
  final TaskRepository tasks;
  final ProjectRepository projects;

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the accent or background is changed in Settings: the
    // surfaces and borders follow the background color.
    return StreamBuilder<Color>(
      stream: settings.watchAccent(),
      initialData: settings.accent,
      builder: (context, accent) => StreamBuilder<Color>(
        stream: settings.watchBackgroundColor(),
        initialData: settings.backgroundColor,
        builder: (context, base) => _app(accent.requireData, base.requireData),
      ),
    );
  }

  Widget _app(Color accent, Color base) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(accent: accent, base: base),
      // The background (picked in Settings) sits behind the whole window,
      // title bar area included. The image (if any) is drawn over the
      // background color, which also shows while it loads; the app's colors
      // follow the color, never the image.
      builder: (context, child) => StreamBuilder<Background?>(
        stream: settings.watchBackground(),
        initialData: settings.background,
        builder: (context, snap) {
          final ImageProvider? image = switch (snap.data) {
            null => null,
            ImageBackground(:final fileName) => FileImage(
              settings.backgroundFile(fileName),
            ),
          };
          return DecoratedBox(
            decoration: BoxDecoration(
              color: base,
              image: image == null
                  ? null
                  : DecorationImage(
                      image: image,
                      fit: BoxFit.cover,
                      // Missing file (deleted outside the app): the color.
                      onError: (_, _) {},
                    ),
            ),
            // Above the navigator, so dialogs (the task form) see it too.
            child: BackgroundImageScope(
              image: image,
              child: ProfilesScope.watching(
                profiles,
                child: CommentsScope.watching(
                  comments,
                  me: () => profiles.current?.id,
                  child: LabelColors.watching(projects, child: child!),
                ),
              ),
            ),
          );
        },
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        // The workspace fills the whole window; the title bar strip floats
        // over it, so the sidebar runs up behind the traffic lights.
        body: Stack(
          children: [
            Positioned.fill(
              child: Workspace(
                store: data.store,
                tasks: tasks,
                projects: projects,
                settings: settings,
                profiles: profiles,
                activity: activity,
                sync: data.sync,
                mcp: mcp,
              ),
            ),
            // Replaces the native title bar: drag to move, double-click to zoom.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: titleBarHeight,
              child: Stack(
                children: [
                  DragToMoveArea(child: const SizedBox.expand()),
                  // Roughly where macOS puts the native buttons.
                  const Positioned(
                    left: 14,
                    top: 0,
                    bottom: 0,
                    child: Center(child: TrafficLights()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
