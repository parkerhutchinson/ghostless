import 'due_date.dart';

/// Marks a [Task.copyWith] argument as not given.
const _keep = Object();

/// Where a task sits on one project's board: its column and its position
/// in that column.
typedef Placement = ({String status, double order});

/// Reads a stored column id. Columns belong to each project's board
/// ([Project.columns]); an id that board doesn't have (a deleted column, or
/// none yet) shows the task in the board's first column.
String _statusFrom(Object? value) => value is String ? value : '';

/// A column on a project's board. Tasks store the column's [id] as their
/// status.
final class TaskColumn {
  const TaskColumn(this.id, this.title);
  final String id;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is TaskColumn && other.id == id && other.title == title;
  @override
  int get hashCode => Object.hash(id, title);
}

/// The columns a new project starts with (and older projects that never
/// changed theirs).
const defaultColumns = [
  TaskColumn('todo', 'To do'),
  TaskColumn('doing', 'In progress'),
  TaskColumn('done', 'Done'),
];

/// A file attached to a task (an image or a PDF): the copy kept in the
/// app's file folder ([file], see [TaskRepository.imageFile]) and the name
/// it was picked with ([name]), shown on its tile.
final class Attachment {
  const Attachment({required this.file, required this.name});

  final String file;
  final String name;

  /// File types that can be attached.
  static const imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'];
  static const extensions = [...imageExtensions, 'pdf'];

  String get extension {
    final dot = file.lastIndexOf('.');
    return dot == -1 ? '' : file.substring(dot + 1).toLowerCase();
  }

  /// Shown as a picture (anything else is a document, opened in its app).
  bool get isImage => imageExtensions.contains(extension);

  Map<String, Object?> toJson() => {'file': file, 'name': name};

  /// Null for anything that isn't a stored attachment.
  static Attachment? fromJson(Object? json) => switch (json) {
    {'file': final String file} when file.isNotEmpty => Attachment(
      file: file,
      name: json['name'] as String? ?? file,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Attachment && other.file == file && other.name == name;
  @override
  int get hashCode => Object.hash(file, name);
}

/// A step within a task: a title and whether it's done. Stored inside its
/// task (see [Task.subtasks]), in the order the user arranged them.
final class Subtask {
  const Subtask({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  Subtask copyWith({String? title, bool? done}) =>
      Subtask(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};

  /// Null for anything that isn't a stored subtask.
  static Subtask? fromJson(Object? json) => switch (json) {
    {'id': final String id} => Subtask(
      id: id,
      title: json['title'] as String? ?? '',
      done: json['done'] == true,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Subtask &&
      other.id == id &&
      other.title == title &&
      other.done == done;
  @override
  int get hashCode => Object.hash(id, title, done);
}

/// A task as stored in the local database (collection `tasks`).
final class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.status = 'todo',
    this.order = 0,
    this.tags = const [],
    this.images = const [],
    this.attachments = const [],
    required this.originId,
    required this.projectIds,
    this.dueDate,
    this.dueTime,
    this.placements = const {},
    this.completedIn = const {},
    this.subtasks = const [],
    this.assigneeId,
    this.reminder,
    required this.createdAt,
  });

  /// When to remind its assignee, in minutes before it's due (0: when
  /// it's due); null for no reminder. Only means something with a
  /// [dueDate]; see `reminderAt` in `lib/reminders/reminders.dart`.
  final int? reminder;

  /// The id of the profile it's assigned to, or null when nobody is.
  /// May name a profile that no longer exists (deleted, or not synced
  /// yet): shown as unassigned.
  final String? assigneeId;

  /// Its steps, in order. One level: subtasks have no subtasks.
  final List<Subtask> subtasks;

  final String id;
  final String title;
  final String description;

  /// The [TaskColumn.id] the task is in.
  final String status;

  /// Position within its column (ascending). Fractional, so a task can be
  /// placed between two others without renumbering the column.
  final double order;

  final List<String> tags;

  /// File names in the app's image folder (see [TaskRepository.imageFile]).
  final List<String> images;

  /// Files attached to it (images and PDFs), in the order added.
  final List<Attachment> attachments;

  /// Every file of its own in the app's file folder: [images] and the
  /// [attachments]' copies.
  Iterable<String> get files => [
    ...images,
    for (final a in attachments) a.file,
  ];

  /// The project the task was created in. It always stays there: only
  /// deleting this project deletes the task.
  final String originId;

  /// Every project the task appears in: [originId] first, then the ones it
  /// was multi-homed to. The same task (one status, one set of details)
  /// shows in each of them.
  final List<String> projectIds;

  /// The projects it was multi-homed to (all but the origin). It can be
  /// taken out of these.
  List<String> get multiHomes => [
    for (final id in projectIds)
      if (id != originId) id,
  ];

  /// Where the task sits in each project it was multi-homed to. Each board
  /// is independent: completing it in one project doesn't move it in
  /// another. ([status] and [order] are its place in the origin project.)
  /// A project missing here (saved before boards were separate) uses the
  /// origin's place until the task is moved there.
  final Map<String, Placement> placements;

  /// The projects where the task is checked off. Completing doesn't move
  /// it: columns are the user's to arrange, so it stays where it is (shown
  /// checked and struck through) until dragged. Per project, like its
  /// place on each board.
  final Set<String> completedIn;

  bool isCompletedIn(String projectId) => completedIn.contains(projectId);

  /// The task with its completion on [projectId]'s board set to [done].
  Task withCompleted(String projectId, bool done) => copyWith(
    completedIn: done
        ? {...completedIn, projectId}
        : ({...completedIn}..remove(projectId)),
  );

  /// Its column and position in [projectId]'s board.
  Placement placementIn(String projectId) => projectId == originId
      ? (status: status, order: order)
      : placements[projectId] ?? (status: status, order: order);

  /// The task as shown on [projectId]'s board: [status] and [order] are its
  /// place there. For display only; never save it (use [withPlacement]).
  Task viewIn(String projectId) {
    final p = placementIn(projectId);
    return copyWith(status: p.status, order: p.order);
  }

  /// The task with its place on [projectId]'s board changed.
  Task withPlacement(String projectId, Placement place) => projectId == originId
      ? copyWith(status: place.status, order: place.order)
      : copyWith(placements: {...placements, projectId: place});

  /// The day it's due (local calendar day, midnight), or null.
  final DateTime? dueDate;

  /// Time of day it's due, in minutes after midnight; null for "any time
  /// that day". Only set along with [dueDate].
  final int? dueTime;

  /// When it's due: [dueDate] at [dueTime], or the end of that day.
  DateTime? get dueAt => switch (dueDate) {
    null => null,
    final d => d.add(Duration(minutes: dueTime ?? 24 * 60 - 1)),
  };

  /// Past due.
  bool isOverdue(DateTime now) => dueAt?.isBefore(now) ?? false;

  /// Past due on [projectId]'s board: overdue, and not checked off there.
  bool isOverdueIn(String projectId, DateTime now) =>
      !isCompletedIn(projectId) && isOverdue(now);

  final DateTime createdAt;

  bool isIn(String projectId) => projectIds.contains(projectId);

  Task copyWith({
    String? title,
    String? description,
    String? status,
    double? order,
    List<String>? tags,
    List<String>? images,
    List<Attachment>? attachments,
    String? originId,
    List<String>? projectIds,
    // Object? so that null can mean "clear it"; omitted means "keep it".
    Object? dueDate = _keep,
    Object? dueTime = _keep,
    Map<String, Placement>? placements,
    Set<String>? completedIn,
    List<Subtask>? subtasks,
    Object? assigneeId = _keep,
    Object? reminder = _keep,
  }) => Task(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    order: order ?? this.order,
    tags: tags ?? this.tags,
    images: images ?? this.images,
    attachments: attachments ?? this.attachments,
    originId: originId ?? this.originId,
    projectIds: projectIds ?? this.projectIds,
    dueDate: dueDate == _keep ? this.dueDate : dueDate as DateTime?,
    dueTime: dueTime == _keep ? this.dueTime : dueTime as int?,
    placements: placements ?? this.placements,
    completedIn: completedIn ?? this.completedIn,
    subtasks: subtasks ?? this.subtasks,
    assigneeId: assigneeId == _keep ? this.assigneeId : assigneeId as String?,
    reminder: reminder == _keep ? this.reminder : reminder as int?,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'description': description,
    'status': status,
    'order': order,
    'tags': tags,
    'images': images,
    'attachments': [for (final a in attachments) a.toJson()],
    'originId': originId,
    'projectIds': projectIds,
    'dueDate': dueDate == null ? null : formatDay(dueDate!),
    'dueTime': dueDate == null || dueTime == null
        ? null
        : formatStoredTime(dueTime!),
    'completedIn': [
      for (final id in completedIn)
        if (projectIds.contains(id)) id,
    ],
    'placements': {
      for (final MapEntry(key: id, value: p) in placements.entries)
        // Only projects the task is still in.
        if (projectIds.contains(id) && id != originId)
          id: {'status': p.status, 'order': p.order},
    },
    'subtasks': [for (final s in subtasks) s.toJson()],
    'assigneeId': assigneeId,
    // No due date, nothing to remind about.
    'reminder': dueDate == null ? null : reminder,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Tolerant of missing fields, so records written by older versions (or
  /// another system via sync) still load.
  factory Task.fromJson(String id, Map<String, Object?> json) {
    final ids = switch (json) {
      {'projectIds': final List ids} => [...ids.whereType<String>()],
      // Saved when a task could only be in one project.
      {'projectId': final String id} when id.isNotEmpty => [id],
      // Saved before projects existed; see TaskRepository.orphans.
      _ => <String>[],
    };
    // Saved before tasks had an origin: the first project was it.
    final origin = json['originId'] as String? ?? ids.firstOrNull ?? '';
    final task = Task(
      id: id,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      // Earlier versions hid completed tasks with a `dismissed` flag.
      status: json['dismissed'] == true ? 'done' : _statusFrom(json['status']),
      order: (json['order'] as num?)?.toDouble() ?? 0,
      tags: [...?(json['tags'] as List?)?.whereType<String>()],
      images: [...?(json['images'] as List?)?.whereType<String>()],
      attachments: [
        for (final a in json['attachments'] as List? ?? const [])
          ?Attachment.fromJson(a),
      ],
      originId: origin,
      projectIds: [
        if (origin.isNotEmpty) origin,
        ...ids.where((p) => p != origin),
      ],
      dueDate: parseDay(json['dueDate']),
      // A time without a day means nothing.
      dueTime: parseDay(json['dueDate']) == null
          ? null
          : parseStoredTime(json['dueTime']),
      placements: {
        if (json['placements'] case final Map stored)
          for (final MapEntry(:key, :value) in stored.entries)
            if (key is String && key != origin && value is Map)
              key: (
                status: _statusFrom(value['status']),
                order: (value['order'] as num?)?.toDouble() ?? 0,
              ),
      },
      subtasks: [
        if (json['subtasks'] case final List stored)
          for (final s in stored) ?Subtask.fromJson(s),
      ],
      assigneeId: switch (json['assigneeId']) {
        final String id when id.isNotEmpty => id,
        _ => null,
      },
      reminder: switch (json['reminder']) {
        final num m when m >= 0 && parseDay(json['dueDate']) != null =>
          m.round(),
        _ => null,
      },
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    return task.copyWith(
      completedIn: switch (json['completedIn']) {
        final List stored => {
          for (final id in stored)
            if (id is String && task.isIn(id)) id,
        },
        // Saved when completing a task moved it to the Done column: it's
        // complete wherever it sits in Done.
        _ => {
          for (final p in task.projectIds)
            if (task.placementIn(p).status == 'done') p,
        },
      },
    );
  }
}
