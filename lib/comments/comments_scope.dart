import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'comment_repository.dart';

/// The comment store, for the task form wherever it opens. Sits above the
/// app's navigator (like [ProfilesScope]), so dialogs see it.
class CommentsScope extends InheritedWidget {
  const CommentsScope({
    super.key,
    required this.repo,
    required this.me,
    this.counts = const {},
    required super.child,
  });

  /// Keeps [child] supplied with [repo] and its live comment counts.
  static Widget watching(
    CommentRepository repo, {
    required String? Function() me,
    required Widget child,
  }) => StreamBuilder<Map<String, int>>(
    stream: repo.watchCounts(),
    initialData: repo.counts(),
    builder: (context, snap) => CommentsScope(
      repo: repo,
      me: me,
      counts: snap.requireData,
      child: child,
    ),
  );

  final CommentRepository repo;

  /// How many comments each task has, for the cards (one map for the
  /// whole board, not a lookup per card).
  final Map<String, int> counts;

  /// [taskId]'s comment count (0 outside a scope).
  static int countOf(BuildContext context, String taskId) =>
      maybeOf(context)?.counts[taskId] ?? 0;

  /// The profile using the app on this Mac: who new comments are by (null
  /// before there's one).
  final String? Function() me;

  /// Null outside a scope (e.g. in tests that don't set one up): the task
  /// form then has no comments.
  static CommentsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommentsScope>();

  @override
  bool updateShouldNotify(CommentsScope old) =>
      old.repo != repo || !mapEquals(old.counts, counts);
}
