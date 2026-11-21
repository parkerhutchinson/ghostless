/// A database-agnostic sync engine.
///
/// Every backend implements [SyncAdapter]; [SyncEngine] moves changes
/// between any two of them, one-way or both ways, with checkpoints so runs
/// resume where they stopped.
library;

export 'src/adapters/contentful_adapter.dart';
export 'src/adapters/memory_adapter.dart';
export 'src/adapters/mysql_adapter.dart' show MySqlAdapter, MySqlDialect;
export 'src/adapters/postgres_adapter.dart';
export 'src/adapters/sanity_adapter.dart';
export 'src/adapters/sql.dart';
export 'src/core/adapter.dart';
export 'src/core/change.dart';
export 'src/core/checkpoint_store.dart';
export 'src/core/engine.dart';
export 'src/core/json.dart' show fingerprint;
export 'src/core/pipeline.dart';
export 'src/core/report.dart';
export 'src/local/local_store.dart';
export 'src/local/sync_controller.dart';
