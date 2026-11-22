import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'activity/activity_repository.dart';
import 'app_theme.dart';
import 'data/app_data.dart';
import 'layout.dart';
import 'sync_status_indicator.dart';
import 'profiles/profile_repository.dart';
import 'profiles/profiles_scope.dart';
import 'projects/project_repository.dart';
import 'projects/workspace.dart';
import 'settings/background.dart';
import 'settings/settings_repository.dart';
import 'tasks/task_repository.dart';
import 'traffic_lights.dart';

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

  // The native window shows through briefly while resizing; match a chosen
  // color.
  settings.watchBackground().listen((b) {
    window.backgroundColor = switch (b) {
      ColorBackground(:final color) => color,
      _ => appBackground,
    }.toNative();
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

  // Due-date reminders for whoever is using this Mac: now, then every
  // minute.
  void remind() {
    if (profiles.current?.id case final id?) {
      activity.addReminders(id, tasks.current());
    }
  }

  remind();
  Timer.periodic(const Duration(minutes: 1), (_) => remind());

  runApp(
    MainApp(
      data: data,
      settings: settings,
      tasks: tasks,
      projects: projects,
      profiles: profiles,
      activity: activity,
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
  });

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
      builder: (context, accent) => StreamBuilder<Background>(
        stream: settings.watchBackground(),
        initialData: settings.background,
        builder: (context, background) =>
            _app(accent.requireData, background.requireData.baseColor),
      ),
    );
  }

  Widget _app(Color accent, Color base) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(accent: accent, base: base),
      // The background (picked in Settings) sits behind the whole window,
      // title bar area included.
      builder: (context, child) => StreamBuilder<Background>(
        stream: settings.watchBackground(),
        initialData: settings.background,
        builder: (context, snap) => DecoratedBox(
          decoration: switch (snap.requireData) {
            ColorBackground(:final color) => BoxDecoration(color: color),
            ImageBackground(:final fileName) => BoxDecoration(
              color: appBackground, // fallback while the image loads
              image: DecorationImage(
                image: FileImage(settings.backgroundFile(fileName)),
                fit: BoxFit.cover,
                // Missing file (deleted outside the app): show the color.
                onError: (_, _) {},
              ),
            ),
            MountainsBackground() => const BoxDecoration(
              color: appBackground,
              image: DecorationImage(
                image: AssetImage(MountainsBackground.asset),
                fit: BoxFit.cover,
              ),
            ),
          },
          // Above the navigator, so dialogs (the task form) see it too.
          child: ProfilesScope.watching(profiles, child: child!),
        ),
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
                  // Close to the right edge (the icon has 4px padding of
                  // its own for a bigger hover target).
                  Positioned(
                    right: 6,
                    top: 0,
                    bottom: 0,
                    child: Center(child: SyncStatusIndicator(sync: data.sync)),
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
