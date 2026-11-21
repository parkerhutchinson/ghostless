import 'package:codename/tasks/due_date.dart';
import 'package:codename/tasks/task.dart';
import 'package:flutter_test/flutter_test.dart';

int t(int h, [int m = 0]) => h * 60 + m;

void main() {
  group('stored values', () {
    test('days round-trip and reject bad dates', () {
      final day = DateTime(2026, 2, 3);
      expect(formatDay(day), '2026-02-03');
      expect(parseDay('2026-02-03'), day);
      expect(parseDay('2026-02-31'), isNull);
      expect(parseDay('Feb 3'), isNull);
      expect(parseDay(null), isNull);
    });

    test('times round-trip and reject bad times', () {
      expect(formatStoredTime(t(9, 5)), '09:05');
      expect(parseStoredTime('09:05'), t(9, 5));
      expect(parseStoredTime('24:00'), isNull);
      expect(parseStoredTime('9:05'), isNull);
      expect(parseStoredTime(905), isNull);
    });
  });

  test('times are shown in 12-hour form', () {
    expect(formatTime(0), '12:00 AM');
    expect(formatTime(t(9, 30)), '9:30 AM');
    expect(formatTime(t(12)), '12:00 PM');
    expect(formatTime(t(23, 30)), '11:30 PM');
  });

  test('the picker offers every half hour of the day', () {
    expect(timeSlots, hasLength(48));
    expect(timeSlots.first, 0);
    expect(timeSlots.last, t(23, 30));
  });

  group('typing a time', () {
    test('empty input lists every slot', () {
      expect(timeSuggestions(''), timeSlots);
    });

    test('an hour alone suggests its AM then PM half hours', () {
      expect(timeSuggestions('2'), [t(2), t(2, 30), t(14), t(14, 30)]);
    });

    test('am/pm narrows it, in any spelling', () {
      for (final input in ['2p', '2pm', '2 PM', '2 p.m.']) {
        expect(timeSuggestions(input), [t(14), t(14, 30)], reason: input);
      }
      expect(parseTime('2a'), t(2));
    });

    test('partial minutes match slots that start with them', () {
      expect(timeSuggestions('2:3'), [t(2, 30), t(14, 30)]);
      expect(parseTime('2:3p'), t(14, 30));
    });

    test('digits without a colon are read as h:mm or hh:mm', () {
      expect(parseTime('230p'), t(14, 30));
      expect(parseTime('1430'), t(14, 30));
    });

    test('24-hour times are understood', () {
      expect(timeSuggestions('14'), [t(14), t(14, 30)]);
      expect(parseTime('14:30'), t(14, 30));
      expect(parseTime('0:30'), t(0, 30));
    });

    test('12 means noon or midnight', () {
      expect(parseTime('12p'), t(12));
      expect(parseTime('12a'), t(0));
    });

    test('an exact time off the half hour is offered as typed', () {
      expect(timeSuggestions('2:15'), [t(2, 15), t(14, 15)]);
      expect(parseTime('2:15 pm'), t(14, 15));
    });

    test('things that are not times give nothing', () {
      for (final input in ['abc', '25', '2:75', '13pm', '2:3x']) {
        expect(timeSuggestions(input), isEmpty, reason: input);
        expect(parseTime(input), isNull, reason: input);
      }
    });
  });

  group('a task\'s due date', () {
    Task task({DateTime? dueDate, int? dueTime, String status = 'todo'}) =>
        Task(
          id: 'x',
          title: 'T',
          status: status,
          originId: 'p',
          projectIds: const ['p'],
          dueDate: dueDate,
          dueTime: dueTime,
          createdAt: DateTime.utc(2026),
        );

    test('is saved and loaded with its time', () {
      final t1 = task(dueDate: DateTime(2026, 11, 20), dueTime: t(14, 30));
      final json = t1.toJson();
      expect(json['dueDate'], '2026-11-20');
      expect(json['dueTime'], '14:30');
      final loaded = Task.fromJson('x', json);
      expect(loaded.dueDate, DateTime(2026, 11, 20));
      expect(loaded.dueTime, t(14, 30));
    });

    test('is optional, and a time without a day is ignored', () {
      expect(Task.fromJson('x', {'title': 'T'}).dueDate, isNull);
      final orphanTime = Task.fromJson('x', {'title': 'T', 'dueTime': '09:00'});
      expect(orphanTime.dueTime, isNull);
      expect(task(dueTime: t(9)).toJson()['dueTime'], isNull);
    });

    test('copyWith keeps it unless told, and can clear it', () {
      final t1 = task(dueDate: DateTime(2026, 11, 20), dueTime: t(9));
      expect(t1.copyWith(title: 'New').dueDate, DateTime(2026, 11, 20));
      expect(t1.copyWith(title: 'New').dueTime, t(9));
      final noTime = t1.copyWith(dueTime: null);
      expect((noTime.dueDate, noTime.dueTime), (DateTime(2026, 11, 20), null));
      final cleared = t1.copyWith(dueDate: null, dueTime: null);
      expect((cleared.dueDate, cleared.dueTime), (null, null));
    });

    test('is overdue after its time, or after its day if no time', () {
      final day = DateTime(2026, 11, 20);
      final timed = task(dueDate: day, dueTime: t(14));
      expect(timed.isOverdue(DateTime(2026, 11, 20, 13, 59)), isFalse);
      expect(timed.isOverdue(DateTime(2026, 11, 20, 14, 1)), isTrue);

      final allDay = task(dueDate: day);
      expect(allDay.isOverdue(DateTime(2026, 11, 20, 23, 0)), isFalse);
      expect(allDay.isOverdue(DateTime(2026, 11, 21)), isTrue);
    });

    test('whatever column it is in, only a due date makes it overdue', () {
      final inDone = task(dueDate: DateTime(2020), status: 'done');
      expect(inDone.isOverdue(DateTime(2026)), isTrue, reason: 'no done state');
      expect(task().isOverdue(DateTime(2026)), isFalse, reason: 'no due date');
    });
  });

  group('typing a date', () {
    final today = DateTime(2026, 11, 19, 15, 30); // a Thursday afternoon
    DateTime? parse(String s) => parseDate(s, today);

    test('dates are shown as "Nov 20, 2026" and read back', () {
      expect(formatDate(DateTime(2026, 11, 20)), 'Nov 20, 2026');
      expect(parse('Nov 20, 2026'), DateTime(2026, 11, 20));
      expect(parse('Fri, Nov 20, 2026'), DateTime(2026, 11, 20));
    });

    test('today and tomorrow', () {
      expect(parse('Today'), DateTime(2026, 11, 19));
      expect(parse('tomorrow'), DateTime(2026, 11, 20));
    });

    test('numeric forms', () {
      expect(parse('11/20'), DateTime(2026, 11, 20));
      expect(parse('11/20/26'), DateTime(2026, 11, 20));
      expect(parse('1/5/2027'), DateTime(2027, 1, 5));
      expect(parse('2026-11-20'), DateTime(2026, 11, 20));
    });

    test('month names, short or long, either order', () {
      expect(parse('nov 20'), DateTime(2026, 11, 20));
      expect(parse('November 20th 2026'), DateTime(2026, 11, 20));
      expect(parse('20 Nov'), DateTime(2026, 11, 20));
      expect(parse('sept 3'), DateTime(2027, 9, 3));
    });

    test('without a year, a day that has passed means next year', () {
      expect(parse('11/19'), DateTime(2026, 11, 19), reason: 'today counts');
      expect(parse('11/18'), DateTime(2027, 11, 18));
      expect(parse('jan 2'), DateTime(2027, 1, 2));
    });

    test('impossible or unreadable dates give null', () {
      for (final s in ['', 'soon', '2/30/2026', '13/1', 'ju 4', '2026-02-31']) {
        expect(parse(s), isNull, reason: s);
      }
    });
  });

  group('calendar grid', () {
    test('always 6 weeks, starting on the week\'s first day', () {
      // November 2026 starts on a Sunday.
      final nov = calendarDays(DateTime(2026, 11));
      expect(nov, hasLength(42));
      expect(nov.first, DateTime(2026, 11, 1));
      expect(nov.last, DateTime(2026, 12, 12), reason: 'next month fills in');
    });

    test('the previous month fills the first row', () {
      // August 2026 starts on a Saturday.
      final aug = calendarDays(DateTime(2026, 8, 20));
      expect(aug.first, DateTime(2026, 7, 26));
      expect(aug[6], DateTime(2026, 8, 1));
      expect(aug.last, DateTime(2026, 9, 5));
      expect(
        aug.every((d) => d.weekday == aug[aug.indexOf(d) % 7].weekday),
        isTrue,
      );
    });

    test('weeks can start on Monday', () {
      final nov = calendarDays(
        DateTime(2026, 11),
        firstWeekday: DateTime.monday,
      );
      expect(nov.first, DateTime(2026, 10, 26));
      expect(nov.first.weekday, DateTime.monday);
    });

    test('days are consecutive midnights, even across daylight saving', () {
      final mar = calendarDays(DateTime(2026, 3));
      for (var i = 1; i < mar.length; i++) {
        expect(mar[i].hour, 0);
        expect(
          DateTime.utc(mar[i].year, mar[i].month, mar[i].day)
              .difference(
                DateTime.utc(mar[i - 1].year, mar[i - 1].month, mar[i - 1].day),
              )
              .inDays,
          1,
        );
      }
    });
  });

  test('overdue dates say how late they are', () {
    final now = DateTime(2026, 11, 20, 15, 0);
    expect(overdueLabel(DateTime(2026, 11, 20), now), isNull); // today
    expect(overdueLabel(DateTime(2026, 11, 21), now), isNull); // tomorrow
    expect(overdueLabel(DateTime(2026, 11, 19), now), 'Due yesterday');
    expect(overdueLabel(DateTime(2026, 11, 17), now), '3 days overdue');
    // Across a month (and a daylight-saving change in early November).
    expect(overdueLabel(DateTime(2026, 10, 30), now), '21 days overdue');
  });
}
