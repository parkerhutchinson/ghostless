/// Due dates and times for tasks.
///
/// A due date is a calendar day (no time zone: "the 20th" stays the 20th
/// wherever you are) with an optional time of day, stored as minutes after
/// midnight.
library;

/// A calendar day, as stored: `2026-11-20`.
String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Reads a stored day; null if missing or malformed.
DateTime? parseDay(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final [y, mo, d] = [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
  final day = DateTime(y, mo, d);
  // Rejects things like 2026-02-31, which DateTime would roll over.
  return day.month == mo && day.day == d ? day : null;
}

/// A time of day, as stored: `14:30`.
String formatStoredTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// Reads a stored time; null if missing or malformed.
int? parseStoredTime(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final (h, min) = (int.parse(m[1]!), int.parse(m[2]!));
  return h < 24 && min < 60 ? h * 60 + min : null;
}

/// A time as shown to people: `2:30 PM`.
String formatTime(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// The times offered in the picker: every 30 minutes, midnight to 11:30 PM.
final timeSlots = [for (var m = 0; m < 24 * 60; m += 30) m];

/// The times matching what's been typed so far, best first; the first one
/// is what the field fills in. Empty input lists every slot.
///
/// Understands `2`, `2:3`, `230`, `2:30p`, `2:30 pm`, `14`, `1430`,
/// `14:30`. A full time that isn't on the half hour (`2:15 pm`) is offered
/// too.
List<int> timeSuggestions(String input) {
  final typed = _parsePartial(input);
  if (typed == null) return input.trim().isEmpty ? timeSlots : const [];
  final (:hour, :minutes, :meridiem) = typed;

  // Which 24-hour hours the typed hour could mean.
  final List<int> hours;
  if (hour >= 1 && hour <= 12) {
    hours = [
      if (meridiem != 'p') hour % 12, // AM
      if (meridiem != 'a') hour % 12 + 12, // PM
    ];
  } else {
    // 0 and 13–23 are 24-hour times; "13pm" makes no sense.
    hours = [if (meridiem == null) hour];
  }
  if (hours.isEmpty) return const [];

  final results = <int>[];
  for (final h in hours) {
    // An exact time, typed in full, that isn't one of the slots.
    if (minutes.length == 2) {
      final m = int.parse(minutes);
      if (m >= 60) return const [];
      results.add(h * 60 + m);
      continue;
    }
    for (final slot in timeSlots.where((s) => s ~/ 60 == h)) {
      final mm = (slot % 60).toString().padLeft(2, '0');
      if (mm.startsWith(minutes)) results.add(slot);
    }
  }
  return results;
}

/// The time to fill in for what's been typed (the best suggestion), or null
/// if it isn't a time.
int? parseTime(String input) => timeSuggestions(input).firstOrNull;

/// Splits typed text into an hour, the minute digits typed so far, and an
/// `a`/`p` if given. Null when it can't be the start of a time.
({int hour, String minutes, String? meridiem})? _parsePartial(String input) {
  final s = input.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
  final m = RegExp(r'^(\d{1,4})(?::(\d{0,2}))?([ap]m?)?$').firstMatch(s);
  if (m == null) return null;
  var digits = m[1]!;
  var minutes = m[2] ?? '';
  // Without a colon, "230" is 2:30 and "1430" is 14:30.
  if (m[2] == null && digits.length > 2) {
    minutes = digits.substring(digits.length - 2);
    digits = digits.substring(0, digits.length - 2);
  }
  final hour = int.parse(digits);
  if (hour > 23) return null;
  return (hour: hour, minutes: minutes, meridiem: m[3]?.substring(0, 1));
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// A day as shown in the date box: `Nov 20, 2026`.
String formatDate(DateTime day) =>
    '${_monthNames[day.month - 1].substring(0, 3)} ${day.day}, ${day.year}';

/// Reads a typed date, or null if it isn't one. Understands `today`,
/// `tomorrow`, `11/20`, `11/20/26`, `11/20/2026`, `2026-11-20`, `Nov 20`,
/// `November 20 2026`, `20 Nov` and what [formatDate] shows (with or
/// without a weekday in front). Without a year, it's the next such day
/// from [today] on.
DateTime? parseDate(String input, DateTime today) {
  today = DateTime(today.year, today.month, today.day);
  var s = input.trim().toLowerCase().replaceAll(',', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  if (s == 'today') return today;
  if (s == 'tomorrow') return today.add(const Duration(days: 1));
  // A leading weekday ("fri nov 20") adds nothing.
  s = s.replaceFirst(RegExp(r'^(mon|tue|wed|thu|fri|sat|sun)[a-z]*\.? '), '');

  int? month, day, year;
  if (RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s) case final m?) {
    (year, month, day) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  } else if (RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?$').firstMatch(s)
      case final m?) {
    (month, day) = (int.parse(m[1]!), int.parse(m[2]!));
    year = m[3] == null ? null : int.parse(m[3]!);
  } else if (RegExp(r'^([a-z]+)\.? (\d{1,2})(?:st|nd|rd|th)?(?: (\d{4}))?$')
          .firstMatch(s)
      case final m?) {
    month = _month(m[1]!);
    day = int.parse(m[2]!);
    year = m[3] == null ? null : int.parse(m[3]!);
  } else if (RegExp(r'^(\d{1,2})(?:st|nd|rd|th)? ([a-z]+)\.?(?: (\d{4}))?$')
          .firstMatch(s)
      case final m?) {
    day = int.parse(m[1]!);
    month = _month(m[2]!);
    year = m[3] == null ? null : int.parse(m[3]!);
  }
  if (month == null || day == null) return null;
  if (year != null && year < 100) year += 2000;

  DateTime? valid(int y) {
    final d = DateTime(y, month!, day!);
    return d.month == month && d.day == day ? d : null;
  }

  if (year != null) return valid(year);
  // No year: this year, or next year if that day has passed.
  final thisYear = valid(today.year);
  if (thisYear != null && !thisYear.isBefore(today)) return thisYear;
  return valid(today.year + 1) ?? thisYear;
}

/// 1–12 for a month name or its first three (or more) letters.
int? _month(String name) {
  if (name.length < 3) return null;
  final i = _monthNames.indexWhere((m) => m.toLowerCase().startsWith(name));
  return i == -1 ? null : i + 1;
}

/// The 42 days (6 weeks) a month's calendar shows: the month itself, with
/// the end of the previous month and the start of the next filling out the
/// first and last rows, so every month has the same grid.
///
/// [firstWeekday] is the column weeks start on: `DateTime.sunday` (7),
/// `DateTime.monday` (1), and so on.
List<DateTime> calendarDays(
  DateTime month, {
  int firstWeekday = DateTime.sunday,
}) {
  final first = DateTime(month.year, month.month);
  final lead = (first.weekday - firstWeekday) % 7;
  // DateTime(y, m, d) rolls over days outside the month, and stays on
  // midnight across daylight-saving changes (unlike adding Durations).
  return [
    for (var i = 0; i < 42; i++)
      DateTime(first.year, first.month, 1 - lead + i),
  ];
}

/// What an overdue task's date says instead of the date itself: "Due
/// yesterday", or "3 days overdue". Null when it's due today (its time has
/// passed, but the day hasn't: the date and time say enough) or later.
/// [due] and [now] are compared by local calendar day.
String? overdueLabel(DateTime due, DateTime now) {
  final dueDay = DateTime(due.year, due.month, due.day);
  final today = DateTime(now.year, now.month, now.day);
  // Rounded: days across a daylight-saving change aren't exactly 24 hours.
  final days = (today.difference(dueDay).inHours / 24).round();
  return switch (days) {
    <= 0 => null,
    1 => 'Due yesterday',
    _ => '$days days overdue',
  };
}
