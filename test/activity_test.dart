import 'dart:io';

import 'package:codename/activity/activity.dart';
import 'package:codename/activity/activity_repository.dart';
import 'package:codename/tasks/task.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late ActivityRepository activity;
  late TaskRepository tasks;
  // Whoever is making changes on this Mac.
  String? actor = 'me';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('activity_test');
    store = LocalStore.inMemory();
    actor = 'me';
    activity = ActivityRepository(store, actorId: () => actor);
    tasks = TaskRepository(store, dir, onChange: activity.recordTaskChange);
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  Task make({String? assignee}) =>
      tasks.create(title: 'Ship it', originId: 'p', assigneeId: assignee);

  group('taskChanges', () {
    final base = Task(
      id: 't',
      title: 'A',
      originId: 'p',
      projectIds: const ['p'],
      createdAt: DateTime.utc(2026),
    );

    test('lists what changed, in a fixed order', () {
      final after = base
          .copyWith(
            title: 'B',
            status: 'doing',
            dueDate: DateTime(2026, 12, 1),
            tags: const ['x'],
          )
          .withCompleted('p', true);
      expect(taskChanges(base, after), [
        TaskChange.renamed,
        TaskChange.column,
        TaskChange.due,
        TaskChange.completed,
        TaskChange.tags,
      ]);
      expect(taskChanges(after, after.withCompleted('p', false)), [
        TaskChange.reopened,
      ]);
    });

    test('moving within a column is not a change', () {
      expect(taskChanges(base, base.copyWith(order: 5)), isEmpty);
    });

    test('describes changes as a sentence', () {
      expect(describeChanges([TaskChange.renamed]), 'Renamed it');
      expect(
        describeChanges([
          TaskChange.renamed,
          TaskChange.due,
          TaskChange.completed,
        ]),
        'Renamed it, changed the due date and checked it off',
      );
    });
  });

  test('assigning someone tells them; the previous assignee hears they '
      'were unassigned', () {
    final t = make(assignee: 'grace');
    expect(activity.current('grace').single.kind, ActivityKind.assigned);
    tasks.assign(t.id, 'alan');
    expect(activity.current('alan').single.kind, ActivityKind.assigned);
    expect(activity.current('grace').first.kind, ActivityKind.unassigned);
  });

  test('changes to your own task, or by you, are not recorded', () {
    final mine = make(assignee: 'me');
    tasks.save(mine.copyWith(title: 'Renamed'));
    expect(activity.current('me'), isEmpty);
    final unassigned = make();
    tasks.save(unassigned.copyWith(title: 'Renamed'));
    expect(store.all(ActivityRepository.collection), isEmpty);
  });

  test('changes to a task assigned to someone else are recorded and '
      'merged while unread', () {
    final t = make(assignee: 'grace');
    activity.markAllRead('grace');
    tasks.save(tasks.get(t.id)!.copyWith(title: 'Ship it now'));
    tasks.toggleCompleted(t.id);
    final updates = activity
        .current('grace')
        .where((a) => a.kind == ActivityKind.updated);
    expect(updates.single.changes, [TaskChange.renamed, TaskChange.completed]);
    expect(updates.single.taskTitle, 'Ship it now');
    expect(updates.single.actorId, 'me');
  });

  test('a different person, a read activity or a later change starts a '
      'new one', () {
    final t = make(assignee: 'grace');
    activity.markAllRead('grace');
    tasks.save(tasks.get(t.id)!.copyWith(title: 'One'));
    actor = 'alan';
    tasks.save(tasks.get(t.id)!.copyWith(title: 'Two'));
    activity.markAllRead('grace');
    tasks.save(tasks.get(t.id)!.copyWith(title: 'Three'));
    final later = DateTime.now().toUtc().add(
      ActivityRepository.mergeWindow * 2,
    );
    activity.recordTaskChange(
      tasks.get(t.id),
      tasks.get(t.id)!.copyWith(description: 'More'),
      now: later,
    );
    expect(
      activity
          .current('grace')
          .where((a) => a.kind == ActivityKind.updated)
          .length,
      4,
    );
  });

  test('edits right after assigning are folded into the assignment', () {
    final t = make(assignee: 'grace');
    tasks.save(tasks.get(t.id)!.copyWith(title: 'Renamed'));
    final only = activity.current('grace').single;
    expect(only.kind, ActivityKind.assigned);
    expect(only.taskTitle, 'Renamed');
  });

  test('marking read, newest first, and pruning old activity', () {
    make(assignee: 'grace');
    make(assignee: 'grace');
    expect(activity.current('grace').every((a) => a.isUnread), isTrue);
    activity.markAllRead('grace');
    expect(activity.current('grace').any((a) => a.isUnread), isFalse);
    final list = activity.current('grace');
    expect(list.first.createdAt.isBefore(list.last.createdAt), isFalse);

    activity.prune(
      now: DateTime.now().toUtc().add(
        ActivityRepository.maxAge + const Duration(days: 1),
      ),
    );
    expect(activity.current('grace'), isEmpty);
  });

  test('deleting a task assigned to someone else tells them; Undo takes '
      'it back', () {
    final t = make(assignee: 'grace');
    activity.markAllRead('grace');
    tasks.delete(t.id);
    expect(activity.current('grace').first.kind, ActivityKind.deleted);
    expect(activity.current('grace').first.taskTitle, 'Ship it');
    // Undo saves the task back.
    tasks.save(t);
    expect(activity.current('grace').map((a) => a.kind), [
      ActivityKind.assigned,
    ]);
  });

  test('a task assigned and deleted straight away leaves nothing', () {
    final t = make(assignee: 'grace');
    tasks.delete(t.id);
    expect(activity.current('grace'), isEmpty);
    final mine = make(assignee: 'me');
    tasks.delete(mine.id);
    expect(activity.current('me'), isEmpty);
  });

  group('due-date reminders', () {
    final day = DateTime(2026, 11, 21);
    Task due({int? time, String assignee = 'me'}) => tasks.create(
      title: 'Report',
      originId: 'p',
      assigneeId: assignee,
      dueDate: day,
      dueTime: time,
    );
    List<ActivityKind> kinds() => [
      for (final a in activity.current('me')) a.kind,
    ];

    test('due today when the day starts, overdue when the time passes, '
        'each once', () {
      final t = due(time: 17 * 60);
      activity.addReminders(
        'me',
        tasks.current(),
        now: day.subtract(const Duration(minutes: 1)),
      );
      expect(kinds(), isEmpty);
      activity.addReminders('me', tasks.current(), now: day);
      activity.addReminders('me', tasks.current(), now: day);
      expect(kinds(), [ActivityKind.dueToday]);
      activity.markAllRead('me');
      final late = day.add(const Duration(hours: 17, minutes: 1));
      activity.addReminders('me', tasks.current(), now: late);
      activity.addReminders('me', tasks.current(), now: late);
      expect(kinds(), [ActivityKind.overdue, ActivityKind.dueToday]);
      expect(activity.current('me').last.isUnread, isFalse, reason: 'kept');
      final reminder = activity.current('me').first;
      expect(reminder.taskId, t.id);
      expect(reminder.dueAt, t.dueAt!.toUtc());
      expect(reminder.actorId, isNull);
    });

    test('a task with no time is overdue after its day ends', () {
      due();
      activity.addReminders(
        'me',
        tasks.current(),
        now: day.add(const Duration(hours: 23)),
      );
      expect(kinds(), [ActivityKind.dueToday]);
      activity.addReminders(
        'me',
        tasks.current(),
        now: day.add(const Duration(days: 1)),
      );
      expect(kinds().first, ActivityKind.overdue);
    });

    test('not for others\' tasks, checked-off tasks, or long overdue ones', () {
      due(assignee: 'grace');
      tasks.toggleCompleted(due().id);
      activity.addReminders('me', tasks.current(), now: day);
      expect(kinds(), isEmpty);
      due();
      activity.addReminders(
        'me',
        tasks.current(),
        now: day.add(
          ActivityRepository.overdueReminderAge + const Duration(days: 2),
        ),
      );
      expect(kinds(), isEmpty);
    });

    test('a new due date gets new reminders', () {
      final t = due();
      activity.addReminders('me', tasks.current(), now: day);
      tasks.save(
        tasks.get(t.id)!.copyWith(dueDate: day.add(const Duration(days: 1))),
      );
      activity.addReminders(
        'me',
        tasks.current(),
        now: day.add(const Duration(days: 1)),
      );
      expect(kinds(), [ActivityKind.dueToday, ActivityKind.dueToday]);
    });
  });

  group('dismissing', () {
    test('hides an item, marks it read, and Undo brings it back', () {
      final t = make(assignee: 'you');
      final a = activity.current('you').single;
      final before = activity.dismiss(a.id)!;
      expect(activity.current('you'), isEmpty);
      expect(before.isUnread, isTrue, reason: 'as it was');
      expect(activity.dismiss(a.id), isNull, reason: 'already hidden');
      activity.restore([before]);
      expect(activity.current('you').single.taskId, t.id);
      expect(activity.current('you').single.isUnread, isTrue);
    });

    test('clear all hides everything; Undo restores it all', () {
      make(assignee: 'you');
      make(assignee: 'you');
      make(assignee: 'them');
      final cleared = activity.dismissAll('you');
      expect(cleared, hasLength(2));
      expect(activity.current('you'), isEmpty);
      expect(activity.current('them'), hasLength(1), reason: 'only yours');
      activity.restore(cleared);
      expect(activity.current('you'), hasLength(2));
    });

    test('clearing many is one write: watchers hear once', () async {
      for (var i = 0; i < 50; i++) {
        make(assignee: 'you');
      }
      final ids = [for (final a in activity.current('you')) a.id];
      var updates = 0;
      final sub = activity.watch('you').skip(1).listen((_) => updates++);
      await pumpEventQueue();
      final cleared = activity.dismissMany(ids.take(30));
      await pumpEventQueue();
      expect(cleared, hasLength(30));
      expect(updates, 1);
      expect(activity.current('you'), hasLength(20));
      // Already hidden, or unknown: skipped.
      expect(activity.dismissMany([ids.first, 'nope']), isEmpty);
      // Marked read too, as a single dismiss does.
      activity.restore(cleared.take(1));
      expect(activity.current('you').any((a) => a.id == ids.first), isTrue);
      await sub.cancel();
    });

    test('a dismissed reminder isn’t added again', () {
      final day = DateTime(2026, 11, 21);
      tasks.create(
        title: 'Report',
        originId: 'p',
        assigneeId: 'me',
        dueDate: day,
      );
      activity.addReminders('me', tasks.current(), now: day);
      activity.dismiss(activity.current('me').single.id);
      activity.addReminders('me', tasks.current(), now: day);
      expect(activity.current('me'), isEmpty);
    });

    test('a change after dismissing shows as a new item', () {
      final t = make(assignee: 'you');
      activity.dismiss(activity.current('you').single.id);
      tasks.save(t.copyWith(title: 'Renamed'));
      final shown = activity.current('you').single;
      expect(shown.kind, ActivityKind.updated);
      expect(shown.isDismissed, isFalse);
    });
  });

  test('JSON round-trip, and unreadable records are skipped', () {
    final a = Activity(
      id: 'a',
      recipientId: 'grace',
      actorId: 'me',
      taskId: 't',
      taskTitle: 'Ship it',
      kind: ActivityKind.updated,
      changes: const [TaskChange.due],
      dueAt: DateTime.utc(2026, 11, 21, 17),
      createdAt: DateTime.utc(2026, 11, 21),
      readAt: DateTime.utc(2026, 11, 22),
    );
    expect(Activity.fromJson('a', a.toJson())!.toJson(), a.toJson());
    expect(Activity.fromJson('x', {'kind': 'exploded'}), isNull);
    expect(
      Activity.fromJson('y', {
        ...a.toJson(),
        'changes': ['due', 'teleported'],
      })!.changes,
      [TaskChange.due],
    );
  });
}
