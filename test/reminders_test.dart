import 'package:codename/reminders/reminders.dart';
import 'package:codename/tasks/task.dart';
import 'package:flutter_test/flutter_test.dart';

Task task(
  String id, {
  DateTime? due,
  int? time,
  int? reminder,
  String? assignee = 'me',
  bool done = false,
  String title = 'Ship it',
}) {
  final t = Task(
    id: id,
    title: title,
    originId: 'p',
    projectIds: const ['p'],
    dueDate: due,
    dueTime: time,
    reminder: reminder,
    assigneeId: assignee,
    createdAt: DateTime(2026),
  );
  return done ? t.withCompleted('p', true) : t;
}

void main() {
  final day = DateTime(2026, 11, 26);

  group('reminderAt', () {
    test('the due time less the reminder', () {
      expect(
        reminderAt(task('a', due: day, time: 15 * 60, reminder: 15)),
        DateTime(2026, 11, 26, 14, 45),
      );
      expect(
        reminderAt(task('a', due: day, time: 15 * 60, reminder: 0)),
        DateTime(2026, 11, 26, 15),
      );
    });

    test('a task due any time that day counts as due at 9 AM', () {
      expect(
        reminderAt(task('a', due: day, reminder: 0)),
        DateTime(2026, 11, 26, 9),
      );
      expect(
        reminderAt(task('a', due: day, reminder: 24 * 60)),
        DateTime(2026, 11, 25, 9),
      );
    });

    test('crosses midnight into the day before', () {
      expect(
        reminderAt(task('a', due: day, time: 30, reminder: 60)),
        DateTime(2026, 11, 25, 23, 30),
      );
    });

    test('none without a reminder or a due date', () {
      expect(reminderAt(task('a', due: day)), isNull);
      expect(reminderAt(task('a', reminder: 15)), isNull);
    });
  });

  test('reminderLabel', () {
    expect(reminderLabel(null), 'None');
    expect(reminderLabel(0), 'At due time');
    expect(reminderLabel(5), '5 minutes before');
    expect(reminderLabel(1), '1 minute before');
    expect(reminderLabel(60), '1 hour before');
    expect(reminderLabel(120), '2 hours before');
    expect(reminderLabel(24 * 60), '1 day before');
    expect(reminderLabel(90), '90 minutes before');
  });

  group('plannedReminders', () {
    final now = DateTime(2026, 11, 26, 8);

    test("only the profile's own, still to come, not checked off", () {
      final plan = plannedReminders(
        [
          task('mine', due: day, time: 12 * 60, reminder: 0),
          task('theirs', due: day, time: 12 * 60, reminder: 0, assignee: 'x'),
          task('nobody', due: day, time: 12 * 60, reminder: 0, assignee: null),
          task('done', due: day, time: 12 * 60, reminder: 0, done: true),
          task('past', due: day, time: 7 * 60, reminder: 0),
          task('none', due: day, time: 12 * 60),
        ],
        profileId: 'me',
        now: now,
      );
      expect(plan.map((r) => r.taskId), ['mine']);
      expect(plan.single.at, DateTime(2026, 11, 26, 12));
      expect(plan.single.id, notificationId('mine'));
    });

    test('soonest first, at most the limit', () {
      final plan = plannedReminders(
        [
          for (var h = 20; h > 10; h--)
            task('t$h', due: day, time: h * 60, reminder: 0),
        ],
        profileId: 'me',
        now: now,
        limit: 3,
      );
      expect(plan.map((r) => r.taskId), ['t11', 't12', 't13']);
    });

    test('nobody signed in: none', () {
      expect(
        plannedReminders(
          [task('a', due: day, time: 12 * 60, reminder: 0)],
          profileId: null,
          now: now,
        ),
        isEmpty,
      );
    });

    test('the text: title, when, project', () {
      final plan = plannedReminders(
        [
          task('a', due: day, time: 15 * 60, reminder: 15, title: ' Pay '),
          task('b', due: day, reminder: 24 * 60, title: ''),
        ],
        profileId: 'me',
        now: now.subtract(const Duration(days: 1)),
        projectName: (_) => 'Office Move',
      );
      // The day-before one goes off first.
      expect(plan[0].title, 'Untitled task');
      expect(plan[0].body, 'Due tomorrow · Office Move');
      expect(plan[1].title, 'Pay');
      expect(plan[1].body, 'Due at 3:00 PM · Office Move');
    });
  });

  test('activeReminders: all still to come, soonest first, no limit', () {
    final now = DateTime(2026, 11, 26, 8);
    final active = activeReminders(
      [
        for (var i = 0; i < 70; i++)
          task('t$i', due: day, time: 9 * 60 + i, reminder: 0),
        task('past', due: day, time: 7 * 60, reminder: 0),
      ],
      profileId: 'me',
      now: now,
    );
    expect(active, hasLength(70));
    expect(active.first.task.id, 't0');
    expect(active.first.at, DateTime(2026, 11, 26, 9));
  });

  group('dueText', () {
    test('at the due time: due now', () {
      final t = task('a', due: day, time: 15 * 60, reminder: 0);
      expect(dueText(t, reminderAt(t)!), 'Due now');
    });

    test('the day before', () {
      final t = task('a', due: day, time: 15 * 60, reminder: 24 * 60);
      expect(dueText(t, reminderAt(t)!), 'Due tomorrow at 3:00 PM');
      final allDay = task('a', due: day, reminder: 24 * 60);
      expect(dueText(allDay, reminderAt(allDay)!), 'Due tomorrow');
    });
  });

  test('notificationId is stable, positive and 31-bit', () {
    expect(notificationId('abc'), notificationId('abc'));
    expect(notificationId('abc'), isNot(notificationId('abd')));
    for (final id in ['', 'x', 'a-very-long-task-id-1234567890']) {
      expect(notificationId(id), inInclusiveRange(0, 0x7fffffff));
    }
  });

  group('Task.reminder', () {
    test('saved and loaded', () {
      final t = task('a', due: day, time: 600, reminder: 30);
      expect(t.toJson()['reminder'], 30);
      expect(Task.fromJson('a', t.toJson()).reminder, 30);
      expect(t.copyWith(title: 'x').reminder, 30);
      expect(t.copyWith(reminder: null).reminder, isNull);
    });

    test('not without a due date', () {
      expect(task('a', reminder: 30).toJson()['reminder'], isNull);
      expect(
        Task.fromJson('a', {'title': 'T', 'reminder': 30}).reminder,
        isNull,
      );
    });

    test('older records: none', () {
      expect(
        Task.fromJson('a', {'title': 'T', 'dueDate': '2026-11-26'}).reminder,
        isNull,
      );
    });
  });
}
