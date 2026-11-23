import 'dart:async';

import '../activity/activity.dart' show taskChanges, TaskChange;
import '../tasks/task.dart';
import '../tasks/task_repository.dart';

/// One change to a task, as the MCP server reports it: numbered in the
/// order they happened ([seq]), so a client can ask for what came after
/// the last one it saw.
final class TaskChangeEvent {
  const TaskChangeEvent({
    required this.seq,
    required this.kind,
    required this.taskId,
    required this.title,
    required this.at,
    this.projectId,
    this.fromStatus,
    this.toStatus,
    this.changes = const [],
  });

  final int seq;

  /// created, deleted, completed, reopened, moved or edited.
  final String kind;
  final String taskId;
  final String title;
  final DateTime at;

  /// The board it happened on (completed, reopened, moved).
  final String? projectId;

  /// The column ids it moved between (moved).
  final String? fromStatus;
  final String? toStatus;

  /// What else changed (edited): title, description, due, subtasks, ...
  final List<String> changes;
}

/// Watches every task and keeps the recent changes to them in order, for
/// the `wait_for_changes` tool. Starts listening when created, so nothing
/// that happens between two calls is missed. Keeps the last [capacity].
final class TaskChangeFeed {
  TaskChangeFeed(this._tasks, {this.capacity = 500})
    : _previous = {for (final t in _tasks.current()) t.id: t} {
    _subscription = _tasks.watch().listen(_diff);
  }

  final TaskRepository _tasks;
  final int capacity;
  Map<String, Task> _previous;
  late final StreamSubscription<List<Task>> _subscription;
  final List<TaskChangeEvent> _events = [];
  final List<Completer<void>> _waiting = [];
  int _seq = 0;

  /// The number of the latest change (0 before any).
  int get latest => _seq;

  /// The changes after [after], oldest first.
  List<TaskChangeEvent> since(int after) => [
    for (final e in _events)
      if (e.seq > after) e,
  ];

  /// The changes after [after]; if there are none yet, waits up to
  /// [timeout] for some (returning empty if none come).
  Future<List<TaskChangeEvent>> wait(int after, Duration timeout) async {
    // Catch up first, in case the watch hasn't delivered something yet.
    _diff(_tasks.current());
    if (since(after) case final ready when ready.isNotEmpty) return ready;
    final signal = Completer<void>();
    _waiting.add(signal);
    await signal.future.timeout(timeout, onTimeout: () {});
    _waiting.remove(signal);
    _diff(_tasks.current());
    return since(after);
  }

  void _diff(List<Task> current) {
    final now = DateTime.now().toUtc();
    final next = {for (final t in current) t.id: t};
    final added = <TaskChangeEvent>[];
    void add(
      String kind,
      Task t, {
      String? projectId,
      String? from,
      String? to,
      List<String> changes = const [],
    }) => added.add(
      TaskChangeEvent(
        seq: ++_seq,
        kind: kind,
        taskId: t.id,
        title: t.title,
        at: now,
        projectId: projectId,
        fromStatus: from,
        toStatus: to,
        changes: changes,
      ),
    );

    for (final after in current) {
      final before = _previous[after.id];
      if (before == null) {
        add('created', after, projectId: after.originId);
        continue;
      }
      for (final p in before.projectIds.where(after.isIn)) {
        final wasDone = before.isCompletedIn(p);
        final isDone = after.isCompletedIn(p);
        if (!wasDone && isDone) add('completed', after, projectId: p);
        if (wasDone && !isDone) add('reopened', after, projectId: p);
        final from = before.placementIn(p).status;
        final to = after.placementIn(p).status;
        if (from != to) add('moved', after, projectId: p, from: from, to: to);
      }
      final other = [
        for (final c in taskChanges(before, after))
          if (c != TaskChange.completed &&
              c != TaskChange.reopened &&
              c != TaskChange.column)
            c.name,
      ];
      if (other.isNotEmpty) add('edited', after, changes: other);
    }
    for (final before in _previous.values) {
      if (!next.containsKey(before.id)) add('deleted', before);
    }
    _previous = next;

    if (added.isEmpty) return;
    _events.addAll(added);
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
    for (final w in [..._waiting]) {
      if (!w.isCompleted) w.complete();
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    for (final w in _waiting) {
      if (!w.isCompleted) w.complete();
    }
  }
}
