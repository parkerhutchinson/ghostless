import 'change.dart';

/// Converts a record's fields from one system's shape to another's.
typedef RecordMapper = Map<String, Object?> Function(Map<String, Object?> data);

enum SyncDirection {
  /// Changes flow from source to target only.
  oneWay,

  /// Changes flow both ways; conflicts go to [SyncPipeline.resolveConflict].
  bidirectional,
}

/// Which side of a pipeline wins a conflict.
enum Side { source, target }

/// Picks the winner when the same record changed on both sides between runs.
typedef ConflictResolver = Side Function(Change source, Change target);

/// Ready-made [ConflictResolver]s.
abstract final class ConflictResolvers {
  /// The most recent change wins; ties go to the source.
  static Side lastWriteWins(Change source, Change target) =>
      target.updatedAt.isAfter(source.updatedAt) ? Side.target : Side.source;

  static Side sourceWins(Change source, Change target) => Side.source;

  static Side targetWins(Change source, Change target) => Side.target;
}

/// Links a collection in the source to one in the target.
final class CollectionMapping {
  const CollectionMapping(
    this.source, {
    String? target,
    this.toTarget,
    this.toSource,
  }) : target = target ?? source;

  /// Collection name in the source adapter.
  final String source;

  /// Collection name in the target adapter (defaults to [source]).
  final String target;

  /// Reshapes source records for the target. Identity when null.
  final RecordMapper? toTarget;

  /// Reshapes target records for the source (two-way only). Identity when null.
  final RecordMapper? toSource;
}

/// A named sync job between two registered adapters.
final class SyncPipeline {
  const SyncPipeline({
    required this.id,
    required this.source,
    required this.target,
    required this.collections,
    this.direction = SyncDirection.oneWay,
    this.resolveConflict = ConflictResolvers.lastWriteWins,
    this.batchSize = 500,
  });

  /// Stable id; checkpoints are stored under it, so renaming restarts the sync.
  final String id;

  /// Registered adapter ids.
  final String source;
  final String target;

  final List<CollectionMapping> collections;
  final SyncDirection direction;
  final ConflictResolver resolveConflict;

  /// Records per pull.
  final int batchSize;
}
