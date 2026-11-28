import '../tasks/due_date.dart';
import '../tasks/task.dart';

/// The reminders a task can have, in minutes before it's due (0: when
/// it's due), in the order the form offers them. Null (no reminder) comes
/// first there.
/// Whether [me] (the current profile) may set a task's reminder: only on
/// tasks assigned to them, since a reminder only ever goes to the assignee.
bool canSetReminder({required String? assigneeId, required String? me}) =>
    me != null && assigneeId == me;

const reminderChoices = [0, 5, 15, 30, 60, 24 * 60];

/// How a reminder reads in the form: "At due time", "15 minutes before",
/// "1 day before". Any other number of minutes still reads sensibly
/// (one set by an assistant).
String reminderLabel(int? minutes) => switch (minutes) {
  null => 'None',
  0 => 'At due time',
  final m when m % (24 * 60) == 0 => _plural(m ~/ (24 * 60), 'day'),
  final m when m % 60 == 0 => _plural(m ~/ 60, 'hour'),
  final m => _plural(m, 'minute'),
};

String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} before';

/// The time of day a task due "any time" that day counts as due, for its
/// reminder: 9 AM.
const allDayReminderTime = 9 * 60;

/// When [task]'s reminder goes off: its due day at its time (9 AM for one
/// due any time that day), less its [Task.reminder]. Null when it has no
/// reminder or no due date.
DateTime? reminderAt(Task task) {
  final day = task.dueDate, before = task.reminder;
  if (day == null || before == null) return null;
  // On the clock (minutes past that midnight, which DateTime rolls over
  // into hours and days), so a clock change doesn't shift it an hour.
  return DateTime(
    day.year,
    day.month,
    day.day,
    0,
    (task.dueTime ?? allDayReminderTime) - before,
  );
}

/// One notification to schedule with macOS.
final class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.taskId,
    required this.at,
    required this.title,
    required this.body,
  });

  /// macOS's id for it (see [notificationId]).
  final int id;
  final String taskId;
  final DateTime at;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.taskId == taskId &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, taskId, at, title, body);

  @override
  String toString() => 'PlannedReminder($taskId at $at: $title / $body)';
}

/// A reminder still to go off: its task and when.
typedef ActiveReminder = ({Task task, DateTime at});

/// [profileId]'s reminders still to come, soonest first: on the tasks
/// assigned to them that aren't checked off (in their origin project).
/// Only the assignee is reminded.
List<ActiveReminder> activeReminders(
  Iterable<Task> tasks, {
  required String? profileId,
  required DateTime now,
}) {
  if (profileId == null) return const [];
  return <ActiveReminder>[
    for (final t in tasks)
      if (t.assigneeId == profileId && !t.isCompletedIn(t.originId))
        if (reminderAt(t) case final at? when at.isAfter(now))
          (task: t, at: at),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// macOS keeps at most 64 scheduled notifications per app; a few spare.
const maxScheduledReminders = 60;

/// The reminders to have scheduled for [profileId] (whoever uses this
/// Mac): their assigned tasks' reminders still to come, soonest first,
/// at most [limit]. Not for tasks checked off (in their origin project),
/// nor for anyone else's: only the assignee is reminded. [projectName]
/// names a task's origin project, for the text (null to leave it out).
List<PlannedReminder> plannedReminders(
  Iterable<Task> tasks, {
  required String? profileId,
  required DateTime now,
  String? Function(String projectId)? projectName,
  int limit = maxScheduledReminders,
}) {
  return [
    for (final (:task, :at) in activeReminders(
      tasks,
      profileId: profileId,
      now: now,
    ).take(limit))
      PlannedReminder(
        id: notificationId(task.id),
        taskId: task.id,
        at: at,
        title: task.title.trim().isEmpty ? 'Untitled task' : task.title.trim(),
        body: [
          dueText(task, at),
          ?projectName?.call(task.originId),
        ].join(' · '),
      ),
  ];
}

/// What a reminder says about when the task's due, as seen when it goes
/// off ([at]): "Due now", "Due at 3:00 PM", "Due today", "Due tomorrow at
/// 9:00 AM", "Due Nov 27".
String dueText(Task task, DateTime at) {
  final day = task.dueDate!, time = task.dueTime;
  final today = DateTime(at.year, at.month, at.day);
  final dueDay = DateTime(day.year, day.month, day.day);
  final days = dueDay.difference(today).inDays;
  if (task.reminder == 0 && time != null) return 'Due now';
  final when = switch (days) {
    0 => time == null ? 'today' : '',
    1 => 'tomorrow',
    _ => formatDate(dueDay),
  };
  final clock = time == null ? '' : 'at ${formatTime(time)}';
  return ['Due', when, clock].where((s) => s.isNotEmpty).join(' ');
}

/// A notification id for [taskId] that's the same every launch (macOS
/// replaces a notification scheduled again under the same id): the
/// FNV-1a hash of the id, kept to 31 bits.
int notificationId(String taskId) {
  var hash = 0x811c9dc5;
  for (final unit in taskId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
