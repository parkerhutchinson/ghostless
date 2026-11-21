/// What happened to a record.
enum ChangeKind { upsert, delete }

/// One record-level change reported by, or sent to, a [SyncAdapter].
///
/// Records are plain maps so every backend — SQL rows, Sanity documents,
/// Contentful entries — can share one shape. Adapters strip their own system
/// fields (ids, timestamps, revisions) out of [data]; [id] and [updatedAt]
/// carry those instead.
final class Change {
  const Change.upsert({
    required this.id,
    required Map<String, Object?> this.data,
    required this.updatedAt,
  }) : kind = ChangeKind.upsert;

  const Change.delete({required this.id, required this.updatedAt})
    : kind = ChangeKind.delete,
      data = null;

  final ChangeKind kind;

  /// Stable id shared by every system in a pipeline.
  final String id;

  /// The record's fields; null for deletes.
  final Map<String, Object?>? data;

  /// When the record last changed in the system that reported it.
  final DateTime updatedAt;

  bool get isDelete => kind == ChangeKind.delete;

  /// Same change with different fields (used when mapping between systems).
  Change withData(Map<String, Object?> data) =>
      Change.upsert(id: id, data: data, updatedAt: updatedAt);

  @override
  String toString() => isDelete
      ? 'Change.delete($id @ ${updatedAt.toIso8601String()})'
      : 'Change.upsert($id @ ${updatedAt.toIso8601String()}, $data)';
}

/// A page of changes returned by [SyncAdapter.pull].
final class ChangePage {
  const ChangePage({
    required this.changes,
    required this.cursor,
    required this.hasMore,
  });

  /// Changes in the order they happened (oldest first).
  final List<Change> changes;

  /// Opaque position to pass to the next pull. Null keeps the previous one
  /// (for example when the page is empty).
  final String? cursor;

  /// Whether another page is immediately available.
  final bool hasMore;
}
