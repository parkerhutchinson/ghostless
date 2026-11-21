import 'change.dart';

/// What an adapter can do. The engine checks these before running a pipeline.
final class AdapterCapabilities {
  const AdapterCapabilities({
    this.canRead = true,
    this.canWrite = true,
    this.reportsDeletes = true,
  });

  final bool canRead;
  final bool canWrite;

  /// Whether [SyncAdapter.pull] reports deleted records. When false, deletes
  /// made in this system never propagate out of it.
  final bool reportsDeletes;
}

/// The one interface every backend implements.
///
/// A *collection* is whatever the backend groups records by: a table in
/// Postgres or MySQL, a document `_type` in Sanity, a content type in
/// Contentful.
abstract interface class SyncAdapter {
  /// Human-readable name for reports and errors.
  String get name;

  AdapterCapabilities get capabilities;

  /// Connects or authenticates. Called once by the engine before first use.
  Future<void> open();

  /// Returns changes in [collection] after [cursor] (from the beginning when
  /// null), oldest first, at most [limit] per page.
  Future<ChangePage> pull(String collection, {String? cursor, int limit = 500});

  /// Applies [changes] to [collection]. Must be idempotent: the engine may
  /// re-send a batch after a failure.
  Future<void> push(String collection, List<Change> changes);

  /// Releases connections. Called by [SyncEngine.close].
  Future<void> close();
}

/// Thrown by adapters when a backend rejects a request.
class SyncAdapterException implements Exception {
  SyncAdapterException(this.adapter, this.message, {this.cause});

  final String adapter;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'SyncAdapterException($adapter): $message${cause == null ? '' : ' ($cause)'}';
}
