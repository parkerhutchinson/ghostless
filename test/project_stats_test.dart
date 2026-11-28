import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_stats.dart';
import 'package:codename/tasks/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026);
  final project = Project(
    id: 'p',
    name: 'Launch',
    createdAt: created,
    columns: const [
      TaskColumn('todo', 'To do'),
      TaskColumn('doing', 'Doing'),
      TaskColumn('done', 'Done'),
    ],
  );

  Task task(
    String id, {
    String status = 'todo',
    String origin = 'p',
    List<String> also = const [],
    Set<String> doneIn = const {},
    String? assignee,
    Map<String, Placement> placements = const {},
  }) => Task(
    id: id,
    title: id,
    status: status,
    originId: origin,
    projectIds: [origin, ...also],
    completedIn: doneIn,
    assigneeId: assignee,
    placements: placements,
    createdAt: created,
  );

  test('counts per column, done out of all, in board order', () {
    final stats = projectStats(project, [
      task('a', doneIn: {'p'}),
      task('b'),
      task('c', status: 'doing'),
      task('d', status: 'done', doneIn: {'p'}),
      task('e', status: 'done', doneIn: {'p'}),
    ]);
    expect(stats.total, 5);
    expect(stats.done, 3);
    expect(stats.open, 2);
    expect(
      [for (final c in stats.columns) c.column.id],
      ['todo', 'doing', 'done'],
    );
    expect(
      [for (final c in stats.columns) (c.total, c.done)],
      [(2, 1), (1, 0), (2, 2)],
    );
    expect(stats.columns[0].doneFraction, 0.5);
  });

  test('an empty column is still there, at zero', () {
    final stats = projectStats(project, [task('a')]);
    expect(stats.columns[2].total, 0);
    expect(stats.columns[2].doneFraction, 0);
  });

  test('only this board: its place and its completion', () {
    final stats = projectStats(project, [
      task('elsewhere', origin: 'q'),
      // Multi-homed here: placed in Doing on this board, done only on
      // the other one.
      task(
        'shared',
        origin: 'q',
        also: ['p'],
        status: 'done',
        doneIn: {'q'},
        placements: {'p': (status: 'doing', order: 0)},
      ),
    ]);
    expect(stats.total, 1);
    expect(stats.done, 0);
    expect(stats.columns[1].total, 1);
  });

  test('a column the board no longer has counts in the first', () {
    final stats = projectStats(project, [task('a', status: 'gone')]);
    expect(stats.columns[0].total, 1);
  });

  test('assignees: most tasks first, with open and done', () {
    final stats = projectStats(project, [
      task('a', assignee: 'sam'),
      task('b', assignee: 'ana', doneIn: {'p'}),
      task('c', assignee: 'ana'),
      task('d'),
      task('e', assignee: 'bo'),
    ]);
    expect(
      [for (final a in stats.assignees) a.assigneeId],
      ['ana', 'bo', 'sam'],
    );
    expect((stats.assignees.first.total, stats.assignees.first.done), (2, 1));
    expect(stats.assignees.first.open, 1);
    expect(stats.unassigned, 1);
  });

  test('top completer: most done, first listed on a tie, none at zero', () {
    const a = AssigneeStats('a', total: 9, done: 2);
    const b = AssigneeStats('b', total: 3, done: 3);
    const c = AssigneeStats('c', total: 4, done: 3);
    expect(topCompleter([a, b, c])?.assigneeId, 'b');
    expect(topCompleter([const AssigneeStats('x', total: 5, done: 0)]), isNull);
    expect(topCompleter([]), isNull);
  });

  test('assigned elsewhere: shared projects with my tasks, per board', () {
    final other = Project(id: 'q', name: 'Other', createdAt: created);
    final empty = Project(id: 'e', name: 'Empty', createdAt: created);
    final mine = Project(
      id: 'm',
      name: 'Personal',
      createdAt: created,
      ownerId: 'me',
    );
    final now = DateTime(2026, 11, 24, 12);
    Task due(
      String id,
      String origin,
      DateTime day, {
      Set<String> doneIn = const {},
    }) => Task(
      id: id,
      title: id,
      originId: origin,
      projectIds: [origin],
      assigneeId: 'me',
      dueDate: day,
      completedIn: doneIn,
      createdAt: created,
    );
    final stats = assignedElsewhere(
      [project, other, empty, mine],
      [
        task('a', assignee: 'me', doneIn: {'p'}),
        // On both boards, done only on this one.
        task('b', assignee: 'me', also: ['q'], doneIn: {'p'}),
        task('c', assignee: 'sam'),
        task('d', origin: 'm', assignee: 'me'),
        due('late', 'q', DateTime(2026, 11, 20)),
        due('lateDone', 'q', DateTime(2026, 11, 20), doneIn: {'q'}),
        due('soon', 'q', DateTime(2026, 12, 1)),
      ],
      'me',
      now: now,
    );
    expect([for (final s in stats) s.project.id], ['p', 'q']);
    expect((stats[0].total, stats[0].done, stats[0].overdue), (2, 2, 0));
    expect((stats[1].total, stats[1].done, stats[1].overdue), (4, 1, 1));
    expect(stats[1].open, 3);
  });

  test('favorites: in the order starred, only existing shared ones', () {
    final a = Project(id: 'a', name: 'A', createdAt: created);
    final b = Project(id: 'b', name: 'B', createdAt: created);
    final mine = Project(
      id: 'm',
      name: 'Mine',
      createdAt: created,
      ownerId: 'me',
    );
    expect(
      [
        for (final p in favoriteProjects(
          [a, b, mine],
          ['b', 'gone', 'm', 'a', 'b'],
        ))
          p.id,
      ],
      ['b', 'a'],
    );
    expect(favoriteProjects([a, b], const []), isEmpty);
  });

  test('description round-trips, and is empty by default', () {
    final withText = Project(
      id: 'p',
      name: 'Launch',
      createdAt: created,
      description: '# Goal\n\nShip **it**.',
    );
    final back = Project.fromJson('p', withText.toJson());
    expect(back.description, '# Goal\n\nShip **it**.');
    expect(Project.fromJson('p', {'name': 'Old'}).description, '');
    expect(back.copyWith(name: 'New').description, withText.description);
  });

  group('companyStats', () {
    final other = Project(id: 'q', name: 'Other', createdAt: created);
    final mine = Project(
      id: 'me',
      name: 'Personal',
      ownerId: 'u',
      createdAt: created,
    );

    test('counts shared projects\' tasks once each, done on their board', () {
      final stats = companyStats(
        [project, other, mine],
        [
          task('a', doneIn: {'p'}),
          task('b', also: ['q']), // on two boards: once
          task('c', origin: 'q', doneIn: {'p'}), // done elsewhere only
          task('d', origin: 'me'), // personal: not the company\'s
        ],
      );
      expect(stats, (total: 3, done: 1, projects: 2));
    });

    test('a personal task multi-homed to a shared board counts there', () {
      final stats = companyStats(
        [project, mine],
        [
          task('a', origin: 'me', also: ['p'], doneIn: {'p'}),
          task('b', origin: 'gone'), // its project was deleted
        ],
      );
      expect(stats, (total: 1, done: 1, projects: 1));
    });
  });
}
