import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import 'comment.dart';

/// Reads and writes task comments in the local store (synced).
class CommentRepository {
  CommentRepository(this._store, {this.onAdded});

  static const collection = 'comments';
  final LocalStore _store;

  /// Called with each comment added here (not ones arriving by sync), to
  /// tell the task's assignee (see [ActivityRepository.recordComment]).
  final void Function(Comment comment)? onAdded;

  /// [taskId]'s comments, oldest first. Updates live.
  Stream<List<Comment>> watch(String taskId) =>
      _store.watch(collection).map((all) => _of(all, taskId));

  /// How many comments each task has (tasks with none aren't listed).
  /// Updates live.
  Stream<Map<String, int>> watchCounts() =>
      _store.watch(collection).map(_counts);

  Map<String, int> counts() => _counts(_store.all(collection));

  static Map<String, int> _counts(Map<String, Map<String, Object?>> all) {
    final counts = <String, int>{};
    for (final record in all.values) {
      if (record['taskId'] case final String task) {
        counts.update(task, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  List<Comment> forTask(String taskId) => _of(_store.all(collection), taskId);

  Comment? get(String id) => switch (_store.get(collection, id)) {
    final json? => Comment.fromJson(id, json),
    null => null,
  };

  /// Adds a comment by [authorId] to [taskId]. Only paragraphs, bold and
  /// links are kept (see [commentMarkdown]). Returns it, or null when
  /// there's nothing to say (blank).
  Comment? add({
    required String taskId,
    required String authorId,
    required String body,
    DateTime? now,
  }) {
    final text = commentMarkdown(body);
    if (text.trim().isEmpty) return null;
    final comment = Comment(
      id: newId(),
      taskId: taskId,
      authorId: authorId,
      body: text,
      createdAt: now ?? DateTime.now().toUtc(),
    );
    _store.put(collection, comment.id, comment.toJson());
    onAdded?.call(comment);
    return comment;
  }

  void delete(String id) => _store.delete(collection, id);

  static List<Comment> _of(
    Map<String, Map<String, Object?>> records,
    String taskId,
  ) => [
    for (final MapEntry(:key, :value) in records.entries)
      if (value['taskId'] == taskId) ?Comment.fromJson(key, value),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
