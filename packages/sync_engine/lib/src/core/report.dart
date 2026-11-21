/// What happened to one collection mapping during a run.
final class CollectionReport {
  CollectionReport(this.source, this.target);

  final String source;
  final String target;

  /// Changes read from either side.
  int pulled = 0;
  int pushedToTarget = 0;
  int pushedToSource = 0;

  /// Two-way only: changes that were the engine's own earlier writes.
  int skippedEchoes = 0;

  /// Two-way only: records changed on both sides since the last run.
  int conflicts = 0;

  Object? error;
  StackTrace? stackTrace;

  bool get ok => error == null;

  @override
  String toString() =>
      '$source → $target: pulled $pulled, pushed $pushedToTarget→target / '
      '$pushedToSource→source, echoes $skippedEchoes, conflicts $conflicts'
      '${ok ? '' : ', FAILED: $error'}';
}

/// The result of [SyncEngine.run].
final class SyncReport {
  SyncReport(this.pipelineId, this.startedAt);

  final String pipelineId;
  final DateTime startedAt;
  late final DateTime finishedAt;
  final List<CollectionReport> collections = [];

  /// True when every collection synced without error.
  bool get ok => collections.every((c) => c.ok);

  @override
  String toString() =>
      'SyncReport($pipelineId, ${finishedAt.difference(startedAt).inMilliseconds}ms'
      '${ok ? '' : ', with errors'})\n  ${collections.join('\n  ')}';
}
