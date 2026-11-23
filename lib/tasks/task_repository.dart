import 'dart:io';

import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';

import 'task.dart';

/// Reads and writes tasks in the local store. Every method saves locally
/// right away; syncing happens in the background.
class TaskRepository {
  TaskRepository(
    this._store,
    Directory appDirectory, {
    String Function(String projectId, String status)? columnFor,
    this.onChange,
  }) : imagesDir = Directory('${appDirectory.path}/images'),
       _columnFor = columnFor ?? ((_, status) => status);

  /// The column a task with a given status shows in on a project's board
  /// ([Project.columnFor]): a status that board has no column for (a
  /// deleted column, or a new multi-home) shows in its first column.
  final String Function(String projectId, String status) _columnFor;

  static const collection = 'tasks';

  /// Called on every save and delete, with the task as it was (null for a
  /// new one) and as it is now (null once deleted): records activity for
  /// its assignee.
  final void Function(Task? before, Task? after)? onChange;

  final LocalStore _store;

  /// Tasks' card images and attachments are copied here.
  final Directory imagesDir;

  /// All tasks, sorted by column order. Updates live.
  Stream<List<Task>> watch() => _store.watch(collection).map(_visible);

  List<Task> current() => _visible(_store.all(collection));

  Task? get(String id) => switch (_store.get(collection, id)) {
    final json? => Task.fromJson(id, json),
    null => null,
  };

  /// Tasks in [projectId] (including ones that are also in other projects),
  /// as stored.
  List<Task> inProject(String projectId) =>
      current().where((t) => t.isIn(projectId)).toList();

  /// [projectId]'s board: its tasks as placed there (see [Task.viewIn]),
  /// in board order. For display; don't save these.
  List<Task> viewsIn(String projectId) => [
    for (final t in viewsOf(current(), projectId))
      t.copyWith(status: _columnFor(projectId, t.status)),
  ];

  /// [tasks] that are in [projectId], as placed there, in board order.
  static List<Task> viewsOf(Iterable<Task> tasks, String projectId) => [
    for (final t in tasks)
      if (t.isIn(projectId)) t.viewIn(projectId),
  ]..sort(_byOrder);

  /// Where a task lands when it's multi-homed to [projectId] (again): the
  /// bottom of the first column, whatever its column elsewhere.
  Placement _newMultiHome(String projectId) =>
      _bottom(projectId, _columnFor(projectId, ''));

  /// A place at the bottom of [status]'s column on [projectId]'s board.
  Placement _bottom(String projectId, String status, {String? except}) {
    final column = viewsIn(projectId)
        .where((t) => t.status == status && t.id != except);
    return (status: status, order: column.isEmpty ? 0 : column.last.order + 1);
  }

  /// Creates a task at the bottom of [status]'s column, in [originId] (the
  /// project it's created in) and multi-homed to [multiHomes].
  Task create({
    required String title,
    String description = '',
    String status = 'todo',
    List<String> tags = const [],
    List<String> images = const [],
    List<Attachment> attachments = const [],
    required String originId,
    List<String> multiHomes = const [],
    DateTime? dueDate,
    int? dueTime,
    List<Subtask> subtasks = const [],
    String? assigneeId,
  }) {
    final home = _bottom(originId, status);
    final task = Task(
      id: newId(),
      title: title,
      description: description,
      status: home.status,
      order: home.order,
      tags: tags,
      images: images,
      attachments: attachments,
      originId: originId,
      projectIds: [
        ...{originId, ...multiHomes},
      ],
      dueDate: dueDate,
      dueTime: dueDate == null ? null : dueTime,
      // Multi-homes start in the first column (see [_newMultiHome]).
      placements: {
        for (final p in multiHomes)
          if (p != originId) p: _newMultiHome(p),
      },
      subtasks: subtasks,
      assigneeId: assigneeId,
      createdAt: DateTime.now().toUtc(),
    );
    save(task);
    return task;
  }

  void save(Task task) {
    final before = onChange == null ? null : get(task.id);
    _store.put(collection, task.id, task.toJson());
    onChange?.call(before, task);
  }

  /// Assigns task [id] to the profile [assigneeId], or to nobody (null).
  void assign(String id, String? assigneeId) {
    final task = get(id);
    if (task != null) save(task.copyWith(assigneeId: assigneeId));
  }

  /// Checks [id] off on [projectId]'s board (its origin's by default), or
  /// unchecks it. It stays in its column. Other boards are unchanged.
  /// Returns the task as it was, for undo.
  Task? toggleCompleted(String id, {String? projectId}) {
    final task = get(id);
    if (task == null) return null;
    final board = projectId ?? task.originId;
    save(task.withCompleted(board, !task.isCompletedIn(board)));
    return task;
  }

  /// Checks subtask [subtaskId] of task [id] off, or unchecks it.
  void toggleSubtask(String id, String subtaskId) {
    final task = get(id);
    if (task == null) return;
    save(
      task.copyWith(
        subtasks: [
          for (final s in task.subtasks)
            s.id == subtaskId ? s.copyWith(done: !s.done) : s,
        ],
      ),
    );
  }

  /// Moves subtask [subtaskId] of task [id] to [index] (counted without
  /// it) among the task's subtasks.
  void moveSubtask(String id, String subtaskId, int index) {
    final task = get(id);
    if (task == null) return;
    final moving = task.subtasks.where((s) => s.id == subtaskId).firstOrNull;
    if (moving == null) return;
    final others = task.subtasks.where((s) => s.id != subtaskId).toList();
    others.insert(index.clamp(0, others.length), moving);
    save(task.copyWith(subtasks: others));
  }

  /// Moves every task in [from]'s column on [projectId]'s board to the
  /// bottom of [to] (when [from] is being deleted). Other boards are
  /// unchanged. Returns the tasks as they were, for undo.
  List<Task> moveColumnTasks(String projectId, String from, String to) {
    final moving = viewsIn(projectId).where((t) => t.status == from).toList();
    final before = [for (final t in moving) get(t.id)!];
    for (final t in moving) {
      move(t.id, to, 1 << 30, projectId: projectId);
    }
    return before;
  }

  /// Copies task [id]: the same details, subtasks and projects, titled
  /// "… (copy)", placed just below the original on every board it's on.
  /// Its images and attachments are copied too, so deleting either task
  /// leaves the other's.
  /// Returns the copy, or null if [id] doesn't exist.
  Future<Task?> duplicate(String id) async {
    final task = get(id);
    if (task == null) return null;
    final images = [
      for (final name in task.images) await addImage(imageFile(name).path),
    ];
    final attachments = [
      for (final a in task.attachments)
        Attachment(file: await addImage(imageFile(a.file).path), name: a.name),
    ];
    final copy = Task.fromJson(newId(), {
      ...task.toJson(),
      'title': '${task.title} (copy)',
      'images': images,
      'attachments': [for (final a in attachments) a.toJson()],
      'subtasks': [
        for (final s in task.subtasks) {...s.toJson(), 'id': newId()},
      ],
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    save(copy);
    // Right after the original in its column, on each board.
    for (final board in task.projectIds) {
      final place = task.placementIn(board);
      final column = viewsIn(board)
          .where((t) => t.status == place.status && t.id != copy.id)
          .toList();
      final index = column.indexWhere((t) => t.id == task.id) + 1;
      move(copy.id, place.status, index, projectId: board);
    }
    return get(copy.id);
  }

  /// Deletes the task and its files (images and attachments). With
  /// [keepImages] the files stay (so an undo can bring the task back
  /// whole); clean them up afterwards with [deleteUnusedImages].
  void delete(String id, {bool keepImages = false}) {
    final task = get(id);
    _store.delete(collection, id);
    if (task != null) onChange?.call(task, null);
    if (keepImages) return;
    for (final name in task?.files ?? const <String>[]) {
      deleteImage(name);
    }
  }

  /// Deletes image files that no task refers to (left behind by a deleted
  /// task, or by quitting before an undo expired).
  void deleteUnusedImages() {
    if (!imagesDir.existsSync()) return;
    final used = {for (final t in current()) ...t.files};
    for (final file in imagesDir.listSync().whereType<File>()) {
      if (!used.contains(file.uri.pathSegments.last)) file.deleteSync();
    }
  }

  /// Multi-homes [id] to [projectId] too. Its position is shared, so it
  /// lands in the same column it's in elsewhere. Returns false if it was
  /// already there.
  bool addToProject(String id, String projectId) {
    final task = get(id);
    if (task == null || task.isIn(projectId)) return false;
    save(
      task
          .copyWith(projectIds: [...task.projectIds, projectId])
          .withPlacement(projectId, _newMultiHome(projectId)),
    );
    return true;
  }

  /// Takes [id] out of [projectId], a project it was multi-homed to.
  /// Returns false if it isn't there, or if that's its origin (it can't
  /// leave the project it was created in).
  bool removeFromProject(String id, String projectId) {
    final task = get(id);
    if (task == null || !task.isIn(projectId) || task.originId == projectId) {
      return false;
    }
    save(
      task.copyWith(
        projectIds: [...task.projectIds.where((p) => p != projectId)],
        placements: {...task.placements}..remove(projectId),
        completedIn: {...task.completedIn}..remove(projectId),
      ),
    );
    return true;
  }

  /// Multi-homes [id] to exactly [multiHomes]; it always stays in its
  /// origin too. Returns false if nothing changed.
  bool setMultiHomes(String id, List<String> multiHomes) {
    final task = get(id);
    if (task == null) return false;
    final ids = [
      ...{task.originId, ...multiHomes},
    ];
    if (ids.length == task.projectIds.length && ids.every(task.isIn)) {
      return false;
    }
    save(
      task.copyWith(
        projectIds: ids,
        placements: {
          for (final p in ids.skip(1))
            p: task.isIn(p) ? task.placementIn(p) : _newMultiHome(p),
        },
      ),
    );
    return true;
  }

  /// Makes [projectId] the origin of [id] (for tasks whose origin is gone).
  void adopt(String id, String projectId) {
    final task = get(id);
    if (task == null) return;
    // Its place on the new origin's board (if it was there) becomes its
    // main place.
    final home = task.placementIn(projectId);
    save(
      task.copyWith(
        originId: projectId,
        projectIds: [
          ...{projectId, ...task.multiHomes},
        ],
        status: home.status,
        order: home.order,
        placements: {...task.placements}..remove(projectId),
      ),
    );
  }

  /// For deleting [projectId]: deletes the tasks created in it, wherever
  /// else they're multi-homed (keeping image files, for undo), and takes
  /// the tasks multi-homed to it out of it. Returns both, as they were, so
  /// an undo can save them back.
  ({List<Task> deleted, List<Task> detached}) removeProject(String projectId) {
    final deleted = <Task>[], detached = <Task>[];
    for (final t in inProject(projectId)) {
      if (t.originId == projectId) {
        delete(t.id, keepImages: true);
        deleted.add(t);
      } else {
        removeFromProject(t.id, projectId);
        detached.add(t);
      }
    }
    return (deleted: deleted, detached: detached);
  }

  /// Tasks whose origin isn't among [projectIds]: saved before projects
  /// existed, or whose origin was deleted on another device. The app gives
  /// them a new origin at startup (see [adopt]).
  List<Task> orphans(Set<String> projectIds) =>
      current().where((t) => !projectIds.contains(t.originId)).toList();

  /// Moves [id] into [status]'s column at [index] (counted without the task
  /// itself) on [projectId]'s board (its origin's by default), giving it an
  /// order between its new neighbours there. Other boards are unchanged.
  void move(String id, String status, int index, {String? projectId}) {
    final task = get(id);
    if (task == null) return;
    final board = projectId ?? task.originId;
    final column = viewsIn(board)
        .where((t) => t.status == status && t.id != id)
        .toList();
    final i = index.clamp(0, column.length);
    final before = i > 0 ? column[i - 1].order : null;
    final after = i < column.length ? column[i].order : null;
    final order = switch ((before, after)) {
      (null, null) => 0.0,
      (final b?, null) => b + 1,
      (null, final a?) => a - 1,
      (final b?, final a?) => (b + a) / 2,
    };
    save(task.withPlacement(board, (status: status, order: order)));
  }

  /// Copies a picked file (an image, or an attachment) into the app's
  /// storage; returns its file name.
  Future<String> addImage(String sourcePath) async {
    await imagesDir.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot == -1 ? '' : sourcePath.substring(dot).toLowerCase();
    final name = '${newId()}$ext';
    await File(sourcePath).copy(imageFile(name).path);
    return name;
  }

  File imageFile(String name) => File('${imagesDir.path}/$name');

  void deleteImage(String name) {
    final file = imageFile(name);
    if (file.existsSync()) file.deleteSync();
  }

  static int _byOrder(Task a, Task b) => a.order != b.order
      ? a.order.compareTo(b.order)
      : a.createdAt.compareTo(b.createdAt);

  static List<Task> _visible(Map<String, Map<String, Object?>> records) => [
    for (final MapEntry(:key, :value) in records.entries)
      Task.fromJson(key, value),
  ].toList()..sort(_byOrder);
}
