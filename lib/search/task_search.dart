import '../projects/project.dart';
import '../tasks/due_date.dart';
import '../tasks/task.dart';

/// Where in a task a search word was found, best first. [date] is the due
/// date, searched only on its own (see [parseDateQuery]).
enum SearchField { title, label, assignee, date }

/// One task found by [searchTasks]: where to show it ([project], the
/// board it opens on, and its [column] there) and how well it matched.
final class SearchHit {
  const SearchHit({
    required this.task,
    required this.project,
    required this.column,
    required this.score,
    required this.fields,
  });

  final Task task;
  final Project project;
  final TaskColumn column;

  /// Lower is better.
  final int score;

  /// Where its words were found.
  final Set<SearchField> fields;

  bool get completed => task.isCompletedIn(project.id);
}

/// The words of [query]: lowercased, split on spaces.
List<String> searchWords(String query) => [
  for (final w in query.toLowerCase().split(RegExp(r'\s+')))
    if (w.isNotEmpty) w,
];

/// Tasks matching [query] in [projects] (the ones the profile can see):
/// every word must be in its title, one of its labels, or its assignee's
/// name ([assigneeNames] by profile id); with [only], in that one alone. Best matches first: title
/// matches (at the start, then at a word's start, then anywhere) before
/// labels before people; open tasks before completed ones; then by
/// title. At most [limit].
List<SearchHit> searchTasks(
  String query,
  Iterable<Task> tasks,
  List<Project> projects, {
  Map<String, String> assigneeNames = const {},
  SearchField? only,
  DateTime? today,
  int firstWeekday = DateTime.sunday,
  int limit = 50,
}) {
  if (only == SearchField.date) {
    return _searchDates(
      query,
      tasks,
      projects,
      today ?? DateTime.now(),
      firstWeekday,
      limit,
    );
  }
  bool searches(SearchField f) =>
      only == f || (only == null && f != SearchField.date);
  final words = searchWords(query);
  if (words.isEmpty) return const [];
  final byId = {for (final p in projects) p.id: p};
  final hits = <SearchHit>[];
  for (final task in tasks) {
    // The board it opens on: its origin if visible, else another of its
    // projects that is.
    final project = _boardOf(task, byId);
    if (project == null) continue;

    final title = task.title.toLowerCase();
    final labels = [for (final l in task.tags) l.toLowerCase()];
    final person = assigneeNames[task.assigneeId]?.toLowerCase() ?? '';
    var score = 0;
    final fields = <SearchField>{};
    var all = true;
    for (final w in words) {
      final int? s;
      final inTitle = searches(SearchField.title);
      if (inTitle && title.startsWith(w)) {
        s = 0;
        fields.add(SearchField.title);
      } else if (inTitle && _atWordStart(title, w)) {
        s = 1;
        fields.add(SearchField.title);
      } else if (inTitle && title.contains(w)) {
        s = 2;
        fields.add(SearchField.title);
      } else if (searches(SearchField.label) &&
          labels.any((l) => l.contains(w))) {
        s = labels.any((l) => l.startsWith(w)) ? 3 : 4;
        fields.add(SearchField.label);
      } else if (searches(SearchField.assignee) && person.contains(w)) {
        s = _atWordStart(person, w) || person.startsWith(w) ? 5 : 6;
        fields.add(SearchField.assignee);
      } else {
        s = null;
      }
      if (s == null) {
        all = false;
        break;
      }
      score += s;
    }
    if (!all) continue;
    final status = project.columnFor(task.placementIn(project.id).status);
    hits.add(
      SearchHit(
        task: task,
        project: project,
        column: project.columns.firstWhere((c) => c.id == status),
        score: score,
        fields: fields,
      ),
    );
  }
  hits.sort((a, b) {
    if (a.score != b.score) return a.score.compareTo(b.score);
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    return a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
  });
  return hits.take(limit).toList();
}

/// The board [task] opens on: its origin if visible, else another of its
/// projects that is.
Project? _boardOf(Task task, Map<String, Project> byId) => [
  task.originId,
  ...task.multiHomes,
].map((id) => byId[id]).nonNulls.firstOrNull;

/// Searching by due date: tasks due on the days [query] means, soonest
/// first (then open before completed, then by title).
List<SearchHit> _searchDates(
  String query,
  Iterable<Task> tasks,
  List<Project> projects,
  DateTime today,
  int firstWeekday,
  int limit,
) {
  final q = parseDateQuery(query, today, firstWeekday: firstWeekday);
  if (q == null) return const [];
  final byId = {for (final p in projects) p.id: p};
  final hits = <SearchHit>[];
  for (final task in tasks) {
    final due = task.dueDate;
    if (due == null || !q.matches(due)) continue;
    final project = _boardOf(task, byId);
    if (project == null) continue;
    if (q.overdue && task.isCompletedIn(project.id)) continue;
    final status = project.columnFor(task.placementIn(project.id).status);
    hits.add(
      SearchHit(
        task: task,
        project: project,
        column: project.columns.firstWhere((c) => c.id == status),
        score: 0,
        fields: const {SearchField.date},
      ),
    );
  }
  hits.sort((a, b) {
    final byDue = a.task.dueAt!.compareTo(b.task.dueAt!);
    if (byDue != 0) return byDue;
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    return a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
  });
  return hits.take(limit).toList();
}

/// What a date search means: which due days match, and whether it's
/// "overdue" (past days, only tasks not done yet).
typedef DateQuery = ({bool Function(DateTime day) matches, bool overdue});

/// Reads a date search, or null when it isn't one:
/// - `today`, `tomorrow`, `yesterday`, `overdue`
/// - `this week`, `next week`, `last week` (weeks starting on
///   [firstWeekday]), `this month`, `next month`, `last month`
/// - a weekday (`fri`, `friday`): the next one, today included
/// - a month (`nov`, `november 2026`): that month (any year without one)
/// - a day, as the due date box takes it (`nov 20`, `11/20`,
///   `2026-11-20`…): without a year, that day in any year.
DateQuery? parseDateQuery(
  String query,
  DateTime today, {
  int firstWeekday = DateTime.sunday,
}) {
  today = DateTime(today.year, today.month, today.day);
  final s = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  DateQuery between(DateTime from, DateTime to) =>
      (matches: (d) => !d.isBefore(from) && d.isBefore(to), overdue: false);
  DateQuery on(DateTime day) =>
      between(day, DateTime(day.year, day.month, day.day + 1));
  DateTime week(int offset) {
    final start = today.day - (today.weekday - firstWeekday) % 7;
    return DateTime(today.year, today.month, start + 7 * offset);
  }

  DateQuery weekOf(int offset) {
    final from = week(offset);
    return between(from, DateTime(from.year, from.month, from.day + 7));
  }

  DateQuery monthOf(int offset) => between(
    DateTime(today.year, today.month + offset),
    DateTime(today.year, today.month + offset + 1),
  );

  switch (s) {
    case 'overdue' || 'past due' || 'late':
      return (matches: (d) => d.isBefore(today), overdue: true);
    case 'yesterday':
      return on(DateTime(today.year, today.month, today.day - 1));
    case 'this week':
      return weekOf(0);
    case 'next week':
      return weekOf(1);
    case 'last week':
      return weekOf(-1);
    case 'this month':
      return monthOf(0);
    case 'next month':
      return monthOf(1);
    case 'last month':
      return monthOf(-1);
  }
  // A weekday alone: the next one, today included.
  if (RegExp(r'^([a-z]{3,})$').firstMatch(s) case final m?) {
    final w = _weekdayNames.indexWhere((n) => n.startsWith(m[1]!));
    if (w != -1) {
      final ahead = (w + 1 - today.weekday) % 7;
      return on(DateTime(today.year, today.month, today.day + ahead));
    }
  }
  // A month alone, maybe with a year.
  if (RegExp(r'^([a-z]{3,})\.?(?: (\d{4}))?$').firstMatch(s) case final m?) {
    final month = _monthNames.indexWhere((n) => n.startsWith(m[1]!));
    if (month != -1) {
      final year = m[2] == null ? null : int.parse(m[2]!);
      return (
        matches: (d) =>
            d.month == month + 1 && (year == null || d.year == year),
        overdue: false,
      );
    }
  }
  // A day.
  final day = parseDate(s, today);
  if (day == null) return null;
  final hasYear = RegExp(r'\d{4}|\d+/\d+/\d+').hasMatch(s);
  if (hasYear || s == 'today' || s == 'tomorrow') return on(day);
  return (
    matches: (d) => d.month == day.month && d.day == day.day,
    overdue: false,
  );
}

const _weekdayNames = [
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', //
  'sunday',
];
const _monthNames = [
  'january', 'february', 'march', 'april', 'may', 'june', 'july', //
  'august', 'september', 'october', 'november', 'december',
];

/// [word] starts one of [text]'s words (after a space or punctuation).
bool _atWordStart(String text, String word) {
  for (var i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + 1)) {
    if (i == 0 || RegExp(r'[\s\-_/.,:;(\[#]').hasMatch(text[i - 1])) {
      return true;
    }
  }
  return false;
}
