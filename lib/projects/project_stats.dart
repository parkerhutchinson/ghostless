import '../tasks/task.dart';
import '../tasks/task_repository.dart';
import 'project.dart';

/// One board column's tasks on the dashboard: how many, and how many of
/// them are done.
final class ColumnStats {
  const ColumnStats(this.column, {required this.total, required this.done});

  final TaskColumn column;
  final int total;
  final int done;

  int get open => total - done;

  /// Done out of all, 0 to 1 (0 for an empty column).
  double get doneFraction => total == 0 ? 0 : done / total;
}

/// Someone with tasks in the project, and how many (open and done).
final class AssigneeStats {
  const AssigneeStats(
    this.assigneeId, {
    required this.total,
    required this.done,
  });

  final String assigneeId;
  final int total;
  final int done;

  int get open => total - done;
}

/// The numbers on a project's dashboard.
final class ProjectStats {
  const ProjectStats({
    required this.total,
    required this.done,
    required this.columns,
    required this.assignees,
    required this.unassigned,
  });

  /// Every task on the board (subtasks aren't counted).
  final int total;

  /// Of those, the ones completed on this board.
  final int done;

  /// Per column, in board order (every column, even empty ones).
  final List<ColumnStats> columns;

  /// The people tasks here are assigned to: most tasks first, then by id
  /// (so the order is steady). Ids that match no profile are left to the
  /// caller to hide.
  final List<AssigneeStats> assignees;

  /// Tasks with no one assigned.
  final int unassigned;

  int get open => total - done;
}

/// Works out [project]'s dashboard from [tasks] (every task; the ones not
/// on this board are skipped). A task's column is where it sits on this
/// board; one in a column the board doesn't have counts in the first
/// column, as the board shows it. Completion is per board
/// ([Task.isCompletedIn]).
ProjectStats projectStats(Project project, Iterable<Task> tasks) {
  final onBoard = TaskRepository.viewsOf(tasks, project.id);
  final total = <String, int>{}, done = <String, int>{};
  final people = <String, ({int total, int done})>{};
  var allDone = 0, unassigned = 0;
  for (final t in onBoard) {
    final column = project.columnFor(t.status);
    final isDone = t.isCompletedIn(project.id);
    total.update(column, (n) => n + 1, ifAbsent: () => 1);
    if (isDone) {
      done.update(column, (n) => n + 1, ifAbsent: () => 1);
      allDone++;
    }
    if (t.assigneeId case final id?) {
      final p = people[id] ?? (total: 0, done: 0);
      people[id] = (total: p.total + 1, done: p.done + (isDone ? 1 : 0));
    } else {
      unassigned++;
    }
  }
  final assignees =
      [
        for (final MapEntry(:key, :value) in people.entries)
          AssigneeStats(key, total: value.total, done: value.done),
      ]..sort((a, b) {
        final byCount = b.total.compareTo(a.total);
        return byCount != 0 ? byCount : a.assigneeId.compareTo(b.assigneeId);
      });
  return ProjectStats(
    total: onBoard.length,
    done: allDone,
    columns: [
      for (final c in project.columns)
        ColumnStats(c, total: total[c.id] ?? 0, done: done[c.id] ?? 0),
    ],
    assignees: assignees,
    unassigned: unassigned,
  );
}

/// Whoever has completed the most of [people]'s tasks (ties go to the one
/// listed first); null when no one has completed any.
AssigneeStats? topCompleter(Iterable<AssigneeStats> people) {
  AssigneeStats? best;
  for (final p in people) {
    if (p.done > (best?.done ?? 0)) best = p;
  }
  return best;
}

/// One project's tasks assigned to someone (for their personal
/// dashboard): how many, how many done there, and how many are past due.
final class AssignedStats {
  const AssignedStats(
    this.project, {
    required this.total,
    required this.done,
    required this.overdue,
  });

  final Project project;
  final int total;
  final int done;

  /// Not done, and past their due date and time.
  final int overdue;

  int get open => total - done;
  double get doneFraction => total == 0 ? 0 : done / total;
}

/// The shared projects among [projects] with tasks assigned to
/// [profileId], in the given (sidebar) order, each with only those tasks
/// counted. Completion is per board, so a task on two boards counts on
/// each as it is there. Personal projects are left out.
List<AssignedStats> assignedElsewhere(
  Iterable<Project> projects,
  Iterable<Task> tasks,
  String profileId, {
  required DateTime now,
}) {
  final mine = [
    for (final t in tasks)
      if (t.assigneeId == profileId) t,
  ];
  return [
    for (final p in projects)
      if (!p.isPersonal)
        if (_assignedIn(p, mine, now) case final s? when s.total > 0) s,
  ];
}

AssignedStats? _assignedIn(Project p, List<Task> mine, DateTime now) {
  var total = 0, done = 0, overdue = 0;
  for (final t in mine) {
    if (!t.isIn(p.id)) continue;
    total++;
    if (t.isCompletedIn(p.id)) {
      done++;
    } else if (t.isOverdue(now)) {
      overdue++;
    }
  }
  return AssignedStats(p, total: total, done: done, overdue: overdue);
}
