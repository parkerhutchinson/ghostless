import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import '../tasks/task.dart';
import '../comments/comment.dart';
import 'activity.dart';

/// Records and reads activity: what other people did to tasks assigned to
/// you, and reminders when they're due. Recorded where the change is made (see [recordTaskChange]) and
/// synced, so it reaches the assignee wherever they use the app.
class ActivityRepository {
  ActivityRepository(this._store, {required this.actorId});

  static const collection = 'activity';

  /// Changes by the same person to the same task within this time, while
  /// still unread, are shown as one activity (the task form saves a task in
  /// several steps; quick edits in a row are one update).
  static const mergeWindow = Duration(minutes: 10);

  /// Activity older than this is deleted (see [prune]).
  static const maxAge = Duration(days: 90);

  final LocalStore _store;

  /// The profile making changes on this Mac.
  final String? Function() actorId;

  /// [recipientId]'s activity, newest first, without what they've
  /// dismissed. Updates live.
  Stream<List<Activity>> watch(String recipientId) =>
      _store.watch(collection).map((all) => _for(all, recipientId));

  List<Activity> current(String recipientId) =>
      _for(_store.all(collection), recipientId);

  /// Hides one item from its recipient (the ✕ on a row). Returns it as it
  /// was, for [restore] (Undo); null if there was nothing to hide.
  Activity? dismiss(String id, {DateTime? now}) {
    final record = _store.get(collection, id);
    final a = record == null ? null : Activity.fromJson(id, record);
    if (a == null || a.isDismissed) return null;
    final at = now ?? DateTime.now().toUtc();
    // Dismissing also counts as seeing it.
    _save(a.copyWith(dismissedAt: at, readAt: a.readAt ?? at));
    return a;
  }

  /// Hides all of [recipientId]'s activity ("Clear all"). Returns what was
  /// hidden, as it was, for [restore].
  List<Activity> dismissAll(String recipientId, {DateTime? now}) =>
      dismissMany([for (final a in current(recipientId)) a.id], now: now);

  /// Hides the items [ids] (a day's Clear) in one write, so a long list
  /// clears at once. Returns what was hidden, as it was, for [restore].
  List<Activity> dismissMany(Iterable<String> ids, {DateTime? now}) {
    final at = now ?? DateTime.now().toUtc();
    final hidden = <Activity>[];
    final records = <String, Map<String, Object?>>{};
    for (final id in ids) {
      final record = _store.get(collection, id);
      final a = record == null ? null : Activity.fromJson(id, record);
      if (a == null || a.isDismissed) continue;
      hidden.add(a);
      // Dismissing also counts as seeing it.
      records[id] = a
          .copyWith(dismissedAt: at, readAt: a.readAt ?? at)
          .toJson();
    }
    _store.putAll(collection, records);
    return hidden;
  }

  /// Puts back what [dismiss] or [dismissAll] hid (Undo).
  void restore(Iterable<Activity> items) =>
      _store.putAll(collection, {for (final a in items) a.id: a.toJson()});

  /// Records what a task change means for its assignees: a new assignee
  /// hears they were assigned, a previous one that they were unassigned,
  /// and an unchanged one what changed, or that it was deleted. Changes
  /// people make to their own tasks aren't recorded. [before] is null for
  /// a new task, [after] for a deleted one.
  void recordTaskChange(Task? before, Task? after, {DateTime? now}) {
    now ??= DateTime.now().toUtc();
    final actor = actorId();
    bool notMe(String? id) => id != null && id != actor;

    if (after == null) {
      if (before == null || !notMe(before.assigneeId)) return;
      final recipient = before.assigneeId!;
      // Assigned and deleted again straight away (an undone duplicate, a
      // slip): there's nothing to tell them.
      final last = _recent(recipient, before.id, actor, now);
      if (last?.kind == ActivityKind.assigned) {
        _store.delete(collection, last!.id);
      } else {
        _add(recipient, actor, before, ActivityKind.deleted, now);
      }
      return;
    }

    final was = before?.assigneeId, isNow = after.assigneeId;
    if (was != isNow) {
      if (notMe(isNow)) {
        // Brought back by Undo right after being deleted: forget the
        // deletion instead.
        final last = before == null
            ? _recent(isNow!, after.id, actor, now)
            : null;
        if (last?.kind == ActivityKind.deleted) {
          _store.delete(collection, last!.id);
        } else {
          _add(isNow!, actor, after, ActivityKind.assigned, now);
        }
      }
      if (notMe(was)) _add(was!, actor, after, ActivityKind.unassigned, now);
      return;
    }
    if (before == null || !notMe(isNow)) return;
    final changes = taskChanges(before, after);
    if (changes.isEmpty) return;

    final last = _recent(isNow!, after.id, actor, now);
    if (last == null ||
        (last.kind != ActivityKind.assigned &&
            last.kind != ActivityKind.updated)) {
      _add(isNow, actor, after, ActivityKind.updated, now, changes: changes);
      return;
    }
    // Just assigned: the follow-up edits are part of handing it over.
    _save(
      last.copyWith(
        taskTitle: after.title,
        createdAt: now,
        changes: last.kind == ActivityKind.assigned
            ? null
            : [
                for (final c in TaskChange.values)
                  if (last.changes.contains(c) || changes.contains(c)) c,
              ],
      ),
    );
  }

  /// Longest preview of a comment kept in its activity.
  static const excerptLength = 140;

  /// Tells [task]'s assignee about [comment] on it, unless they wrote it.
  void recordComment(Task? task, Comment comment) {
    final recipient = task?.assigneeId;
    if (task == null || recipient == null || recipient == comment.authorId) {
      return;
    }
    final text = comment.plainText;
    _save(
      Activity(
        id: newId(),
        recipientId: recipient,
        actorId: comment.authorId,
        taskId: task.id,
        taskTitle: task.title,
        kind: ActivityKind.commented,
        excerpt: text.length <= excerptLength
            ? text
            : '${text.substring(0, excerptLength).trimRight()}…',
        createdAt: comment.createdAt,
      ),
    );
  }

  /// [recipientId]'s latest activity about [taskId], if it can still be
  /// merged with a change [actor] is making: unread, by them, and within
  /// [mergeWindow].
  Activity? _recent(
    String recipientId,
    String taskId,
    String? actor,
    DateTime now,
  ) {
    // Dismissed ones count: an update right after dismissing a row starts
    // a new one rather than vanishing into the hidden one.
    final last = _for(
      _store.all(collection),
      recipientId,
      dismissed: true,
    ).where((a) => a.taskId == taskId).firstOrNull;
    return last != null &&
            last.isUnread &&
            !last.isDismissed &&
            !last.kind.isReminder &&
            last.actorId == actor &&
            now.difference(last.createdAt) < mergeWindow
        ? last
        : null;
  }

  /// Overdue reminders are only added this long after the due time, so
  /// long-forgotten tasks don't all show up at once.
  static const overdueReminderAge = Duration(days: 7);

  /// Adds due-date reminders for [recipientId]'s tasks among [tasks], once
  /// each: "due today" when the due day starts, "overdue" when the due
  /// time passes. Not for tasks checked off on any board. Run regularly
  /// (the app does every minute) on the Mac they're using; reminders are
  /// for everyone's own tasks too, whoever set the date.
  void addReminders(String recipientId, Iterable<Task> tasks, {DateTime? now}) {
    now ??= DateTime.now();
    for (final t in tasks) {
      final due = t.dueAt;
      if (due == null ||
          t.assigneeId != recipientId ||
          t.completedIn.isNotEmpty) {
        continue;
      }
      if (!now.isBefore(due)) {
        if (now.difference(due) <= overdueReminderAge) {
          _remind(recipientId, t, ActivityKind.overdue, now);
        }
      } else if (!now.isBefore(t.dueDate!)) {
        _remind(recipientId, t, ActivityKind.dueToday, now);
      }
    }
  }

  /// Adds the reminder unless it exists. The id comes from the task, the
  /// kind and the due time, so each is added once (even by two Macs), and
  /// a new due date gets new reminders.
  void _remind(String recipientId, Task task, ActivityKind kind, DateTime now) {
    final due = task.dueAt!;
    final id = 'reminder-${kind.name}-${task.id}-${due.millisecondsSinceEpoch}';
    if (_store.get(collection, id) != null) return;
    _save(
      Activity(
        id: id,
        recipientId: recipientId,
        actorId: null,
        taskId: task.id,
        taskTitle: task.title,
        kind: kind,
        dueAt: due.toUtc(),
        createdAt: now.toUtc(),
      ),
    );
  }

  /// Marks all of [recipientId]'s unread activity as seen.
  void markAllRead(String recipientId, {DateTime? now}) {
    now ??= DateTime.now().toUtc();
    for (final a in current(recipientId).where((a) => a.isUnread)) {
      _save(a.copyWith(readAt: now));
    }
  }

  /// Deletes activity older than [maxAge], so the collection doesn't grow
  /// forever.
  void prune({DateTime? now}) {
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(maxAge);
    for (final MapEntry(:key, :value) in _store.all(collection).entries) {
      final a = Activity.fromJson(key, value);
      if (a == null || a.createdAt.isBefore(cutoff)) {
        _store.delete(collection, key);
      }
    }
  }

  void _add(
    String recipientId,
    String? actorId,
    Task task,
    ActivityKind kind,
    DateTime now, {
    List<TaskChange> changes = const [],
  }) => _save(
    Activity(
      id: newId(),
      recipientId: recipientId,
      actorId: actorId,
      taskId: task.id,
      taskTitle: task.title,
      kind: kind,
      changes: changes,
      createdAt: now,
    ),
  );

  void _save(Activity a) => _store.put(collection, a.id, a.toJson());

  static List<Activity> _for(
    Map<String, Map<String, Object?>> records,
    String recipientId, {
    bool dismissed = false,
  }) => [
    for (final MapEntry(:key, :value) in records.entries)
      if (Activity.fromJson(key, value) case final a?
          when a.recipientId == recipientId && (dismissed || !a.isDismissed))
        a,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
