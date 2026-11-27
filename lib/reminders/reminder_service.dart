import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

import '../profiles/profile_repository.dart';
import '../projects/project_repository.dart';
import '../tasks/task_repository.dart';
import 'reminders.dart';

/// Task reminders as macOS notifications: local ones, scheduled with the
/// system, so they go off at their time even when the app is closed. No
/// server and no push (APNs).
///
/// Keeps what's scheduled in step with [plannedReminders] for whoever
/// uses this Mac: on launch, then whenever tasks, projects or the profile
/// change (here or through sync). A task changed on another Mac while
/// this one's app is closed is caught up the next time it opens.
class ReminderService {
  ReminderService({
    required this.tasks,
    required this.projects,
    required this.profiles,
  });

  final TaskRepository tasks;
  final ProjectRepository projects;
  final ProfileRepository profiles;

  final _plugin = FlutterLocalNotificationsPlugin();

  /// What's scheduled now, by notification id.
  final _scheduled = <int, PlannedReminder>{};

  final _opened = StreamController<String>.broadcast();

  /// The task id of each reminder clicked while the app runs.
  Stream<String> get opened => _opened.stream;

  /// The task of the reminder that launched the app, if one did. Taken
  /// (and cleared) by whoever opens it.
  String? takeLaunchTask() {
    final id = _launchTask;
    _launchTask = null;
    return id;
  }

  String? _launchTask;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _debounce;

  /// Changes to macOS's schedule, one at a time.
  Future<void> _queue = Future.value();

  Future<void> start() async {
    try {
      await _plugin.initialize(
        // Asked for when a reminder is first set (see [requestPermission]),
        // not at launch.
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload case final id? when id.isNotEmpty) _opened.add(id);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _launchTask = launch?.notificationResponse?.payload;
      }
      // Whatever an earlier launch left scheduled is redone from scratch.
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      // No notifications (not on a Mac, or in a test): nothing to do.
      return;
    }
    _subscriptions.addAll([
      tasks.watch().listen((_) => _schedule()),
      projects.watch().listen((_) => _schedule()),
      profiles.watchCurrent().listen((_) => _schedule()),
    ]);
    _apply();
    // Tops up the schedule as reminders go off (only the soonest
    // [maxScheduledReminders] are scheduled).
    _subscriptions.add(
      Stream<void>.periodic(const Duration(minutes: 15))
          .listen((_) => _schedule()),
    );
  }

  /// Asks macOS for permission to show notifications (once; after that
  /// macOS answers from the person's choice, in System Settings ›
  /// Notifications). True if allowed.
  Future<bool> requestPermission() async {
    try {
      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      return await mac?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Batches a burst of changes (a sync bringing many tasks) into one
  /// pass.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _apply);
  }

  void _apply() {
    final plan = plannedReminders(
      tasks.current(),
      profileId: profiles.current?.id,
      now: DateTime.now(),
      projectName: (id) => projects.get(id)?.name,
    );
    _queue = _queue.then((_) => _sync(plan)).catchError((_) {});
  }

  Future<void> _sync(List<PlannedReminder> plan) async {
    final wanted = {for (final r in plan) r.id: r};
    for (final id in [..._scheduled.keys]) {
      if (!wanted.containsKey(id)) {
        await _plugin.cancel(id: id);
        _scheduled.remove(id);
      }
    }
    for (final r in plan) {
      if (_scheduled[r.id] == r) continue;
      // Passed while waiting its turn: it would be refused.
      if (!r.at.isAfter(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        // The moment it goes off, in UTC: the same instant wherever the
        // Mac is.
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.taskId,
      );
      _scheduled[r.id] = r;
    }
  }

  void dispose() {
    _debounce?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _opened.close();
  }
}

/// Gives widgets below it (the task form, in a dialog) the
/// [ReminderService]: above the navigator, like `CommentsScope`.
class RemindersScope extends InheritedWidget {
  const RemindersScope({
    super.key,
    required this.service,
    required super.child,
  });

  final ReminderService service;

  static ReminderService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemindersScope>()?.service;

  @override
  bool updateShouldNotify(RemindersScope old) => old.service != service;
}
