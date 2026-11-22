import '../tasks/task.dart';

/// What happened to a task, from its assignee's point of view.
enum ActivityKind {
  /// The task was assigned to them.
  assigned,

  /// The task was taken off them (unassigned, or given to someone else).
  unassigned,

  /// Someone changed a task assigned to them ([Activity.changes]).
  updated,

  /// Someone deleted a task assigned to them.
  deleted,

  /// Reminder: a task assigned to them is due today ([Activity.dueAt]).
  dueToday,

  /// Reminder: a task assigned to them is past due ([Activity.dueAt]).
  overdue;

  /// A reminder from the app, not something a person did.
  bool get isReminder => this == dueToday || this == overdue;
}

/// One kind of change to a task, as listed in an [ActivityKind.updated]
/// activity. Moving a task within its column isn't one: it's not news.
enum TaskChange {
  renamed('renamed it'),
  description('edited the description'),
  column('moved it to another column'),
  due('changed the due date'),
  completed('checked it off'),
  reopened('unchecked it'),
  subtasks('changed the subtasks'),
  tags('changed the labels'),
  images('changed the card image'),
  projects('changed its projects');

  const TaskChange(this.phrase);

  /// Lowercase, to go in a sentence: "renamed it".
  final String phrase;
}

/// "Renamed it, changed the due date and checked it off".
String describeChanges(List<TaskChange> changes) {
  final phrases = [for (final c in changes) c.phrase];
  if (phrases.isEmpty) return '';
  final text = phrases.length == 1
      ? phrases.single
      : '${phrases.sublist(0, phrases.length - 1).join(', ')} and '
            '${phrases.last}';
  return text[0].toUpperCase() + text.substring(1);
}

/// The changes between two versions of a task, in [TaskChange] order.
/// Empty when only its position within a column changed.
List<TaskChange> taskChanges(Task before, Task after) {
  final boards = before.projectIds.where(after.isIn);
  bool completedSomewhere(Task a, Task b) =>
      boards.any((p) => b.isCompletedIn(p) && !a.isCompletedIn(p));
  return [
    if (before.title != after.title) TaskChange.renamed,
    if (before.description != after.description) TaskChange.description,
    if (boards.any(
      (p) => before.placementIn(p).status != after.placementIn(p).status,
    ))
      TaskChange.column,
    if (before.dueDate != after.dueDate || before.dueTime != after.dueTime)
      TaskChange.due,
    if (completedSomewhere(before, after)) TaskChange.completed,
    if (completedSomewhere(after, before)) TaskChange.reopened,
    if (!_sameList(before.subtasks, after.subtasks)) TaskChange.subtasks,
    if (!_sameList(before.tags, after.tags)) TaskChange.tags,
    if (!_sameList(before.images, after.images)) TaskChange.images,
    if (!_sameList(before.projectIds, after.projectIds)) TaskChange.projects,
  ];
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Something that happened to a task assigned to [recipientId]: done by
/// someone else ([actorId]), or a due-date reminder. Stored in the synced `activity` collection, so
/// it reaches the recipient on whichever Mac they use.
final class Activity {
  const Activity({
    required this.id,
    required this.recipientId,
    required this.actorId,
    required this.taskId,
    required this.taskTitle,
    required this.kind,
    this.changes = const [],
    this.dueAt,
    required this.createdAt,
    this.readAt,
    this.dismissedAt,
  });

  final String id;

  /// The profile it's for: the task's assignee.
  final String recipientId;

  /// The profile that made the change; null when it was made without one,
  /// and for reminders.
  final String? actorId;

  final String taskId;

  /// The task's title at the time, shown if the task is gone.
  final String taskTitle;

  final ActivityKind kind;

  /// What changed, for [ActivityKind.updated].
  final List<TaskChange> changes;

  /// When the task was due, for reminders.
  final DateTime? dueAt;

  /// When it happened (the latest change, for merged updates).
  final DateTime createdAt;

  /// When the recipient saw it; null while unread.
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// When the recipient dismissed it; it's hidden from then on. Kept (not
  /// deleted) so a reminder isn't added again, until [prune] removes it.
  final DateTime? dismissedAt;

  bool get isDismissed => dismissedAt != null;

  Activity copyWith({
    String? taskTitle,
    List<TaskChange>? changes,
    DateTime? createdAt,
    DateTime? readAt,
    DateTime? dismissedAt,
  }) => Activity(
    id: id,
    recipientId: recipientId,
    actorId: actorId,
    taskId: taskId,
    taskTitle: taskTitle ?? this.taskTitle,
    kind: kind,
    changes: changes ?? this.changes,
    dueAt: dueAt,
    createdAt: createdAt ?? this.createdAt,
    readAt: readAt ?? this.readAt,
    dismissedAt: dismissedAt ?? this.dismissedAt,
  );

  Map<String, Object?> toJson() => {
    'recipientId': recipientId,
    'actorId': actorId,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'kind': kind.name,
    'changes': [for (final c in changes) c.name],
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'readAt': readAt?.toUtc().toIso8601String(),
    'dismissedAt': dismissedAt?.toUtc().toIso8601String(),
  };

  /// Null for a record this version can't read (no recipient or task, or a
  /// kind it doesn't know). Unknown changes are skipped.
  static Activity? fromJson(String id, Map<String, Object?> json) {
    final kind = ActivityKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final recipient = json['recipientId'], task = json['taskId'];
    if (kind == null || recipient is! String || task is! String) return null;
    return Activity(
      id: id,
      recipientId: recipient,
      actorId: json['actorId'] as String?,
      taskId: task,
      taskTitle: json['taskTitle'] as String? ?? '',
      kind: kind,
      changes: [
        if (json['changes'] case final List stored)
          for (final name in stored)
            ...TaskChange.values.where((c) => c.name == name),
      ],
      dueAt: DateTime.tryParse(json['dueAt'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
      dismissedAt: DateTime.tryParse(json['dismissedAt'] as String? ?? ''),
    );
  }
}
