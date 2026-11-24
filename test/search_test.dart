import 'package:codename/projects/project.dart';
import 'package:codename/search/task_search.dart';
import 'package:codename/tasks/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026);
  final work = Project(id: 'w', name: 'Work', createdAt: created);
  final mine = Project(
    id: 'm',
    name: 'Mine',
    createdAt: created,
    ownerId: 'me',
  );

  Task task(
    String id,
    String title, {
    String project = 'w',
    List<String> tags = const [],
    String? assignee,
    bool done = false,
    List<String> also = const [],
  }) => Task(
    id: id,
    title: title,
    originId: project,
    projectIds: [project, ...also],
    tags: tags,
    assigneeId: assignee,
    completedIn: done ? {project} : const {},
    createdAt: created,
  );

  final tasks = [
    task('1', 'Write launch plan', tags: ['docs'], assignee: 'sam'),
    task('2', 'Plan the offsite', tags: ['events']),
    task('3', 'Fix login bug', tags: ['bug', 'auth'], assignee: 'ana'),
    task('4', 'Explain the plan', done: true),
    task('5', 'Secret plan', project: 't'),
    task('6', 'Grocery plan', project: 'm'),
    task('7', 'Shared plan', project: 't', also: ['w']),
  ];
  const names = {'sam': 'Sam Lee', 'ana': 'Ana Ruiz'};
  // Theirs is another profile's personal project: not visible.
  final visible = [work, mine];

  List<String> ids(String q) => [
    for (final h in searchTasks(q, tasks, visible, assigneeNames: names))
      h.task.id,
  ];

  test('finds by title, best matches first', () {
    // Starts with "plan", then "plan" starting a word (open before
    // completed), then by title.
    expect(ids('plan'), ['2', '6', '7', '1', '4']);
  });

  test('finds by label and by person', () {
    expect(ids('auth'), ['3']);
    expect(ids('docs'), ['1']);
    expect(ids('ana'), ['3']);
    expect(ids('lee'), ['1']);
  });

  test('every word has to match somewhere', () {
    expect(ids('plan sam'), ['1']);
    expect(ids('bug sam'), isEmpty);
  });

  test('only visible projects; a multi-homed task opens where visible', () {
    expect(ids('secret'), isEmpty);
    final shared = searchTasks('shared', tasks, visible).single;
    expect(shared.project.id, 'w');
    expect(shared.column.id, 'todo');
  });

  test('one field only, when picked', () {
    List<String> only(String q, SearchField f) => [
      for (final h in searchTasks(
        q,
        tasks,
        visible,
        assigneeNames: names,
        only: f,
      ))
        h.task.id,
    ];
    // "bug" is in task 3's title and its label.
    expect(only('bug', SearchField.title), ['3']);
    expect(only('auth', SearchField.title), isEmpty);
    expect(only('auth', SearchField.label), ['3']);
    expect(only('plan', SearchField.label), isEmpty);
    expect(only('sam', SearchField.assignee), ['1']);
    expect(only('sam', SearchField.title), isEmpty);
  });

  test('nothing for an empty query', () {
    expect(ids('   '), isEmpty);
  });

  group('by date', () {
    // Monday, Nov 23 2026.
    final today = DateTime(2026, 11, 23);
    Task due(String id, DateTime day, {bool done = false}) => Task(
      id: id,
      title: 'Task $id',
      originId: 'w',
      projectIds: const ['w'],
      dueDate: day,
      completedIn: done ? const {'w'} : const {},
      createdAt: created,
    );
    final dated = [
      due('past', DateTime(2026, 11, 20)),
      due('pastDone', DateTime(2026, 11, 19), done: true),
      due('today', DateTime(2026, 11, 23)),
      due('fri', DateTime(2026, 11, 27)),
      due('nextWeek', DateTime(2026, 12, 1)),
      due('lastYear', DateTime(2025, 11, 27)),
      task('none', 'No date'),
    ];
    List<String> find(String q, {int firstWeekday = DateTime.sunday}) => [
      for (final h in searchTasks(
        q,
        dated,
        [work],
        only: SearchField.date,
        today: today,
        firstWeekday: firstWeekday,
      ))
        h.task.id,
    ];

    test('days, soonest first', () {
      expect(find('today'), ['today']);
      expect(find('2026-11-27'), ['fri']);
      expect(find('Nov 27 2026'), ['fri']);
      // No year: that day in any year.
      expect(find('nov 27'), ['lastYear', 'fri']);
      expect(find('11/27'), ['lastYear', 'fri']);
      expect(find('friday'), ['fri']);
      expect(find('fri'), ['fri']);
    });

    test('ranges', () {
      // Weeks from Sunday: Nov 22 – 28.
      expect(find('this week'), ['today', 'fri']);
      expect(find('next week'), ['nextWeek']);
      expect(find('last week'), ['pastDone', 'past']);
      // From Monday, Nov 16 – 22 is last week.
      expect(find('this month'), ['pastDone', 'past', 'today', 'fri']);
      expect(find('next month'), ['nextWeek']);
      expect(find('nov'), ['lastYear', 'pastDone', 'past', 'today', 'fri']);
      expect(find('november 2025'), ['lastYear']);
    });

    test('overdue leaves out done tasks', () {
      expect(find('overdue'), ['lastYear', 'past']);
    });

    test('not a date: nothing', () {
      expect(find('launch'), isEmpty);
      expect(find(''), isEmpty);
    });
  });
}
