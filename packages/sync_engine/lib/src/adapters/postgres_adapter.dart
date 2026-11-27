import 'dart:async';

import 'package:postgres/postgres.dart';

import '../core/adapter.dart';
import '../core/change.dart';
import '../core/schema.dart';
import 'sql.dart';

/// Syncs Postgres tables. Collection names are table names (`schema.table`
/// works too); see [SqlTable] for what each table needs.
class PostgresAdapter implements SyncAdapter, SchemaInspector {
  PostgresAdapter({
    required this.endpoint,
    this.settings,
    this.tables = const {},
    this.defaultTable = const SqlTable(),
  });

  final Endpoint endpoint;
  final ConnectionSettings? settings;

  /// Per-table column settings; tables not listed use [defaultTable].
  final Map<String, SqlTable> tables;
  final SqlTable defaultTable;

  static const _dialect = PostgresDialect();
  Connection? _connection;

  @override
  String get name => 'postgres:${endpoint.host}/${endpoint.database}';

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities();

  /// The connection, opened again if it was lost (the network dropped,
  /// the server restarted): a dead one is never reused, or no sync could
  /// succeed until the app restarted.
  Future<Connection> _conn() async {
    final c = _connection;
    if (c != null && c.isOpen) return c;
    _connection = null;
    unawaited(c?.close().catchError((_) {}));
    return _connection = await Connection.open(endpoint, settings: settings);
  }

  /// Runs [f] on the connection. If it fails, the connection is dropped
  /// (closed in the background): after a network error it may still say
  /// it's open, so the next sync starts on a fresh one.
  Future<T> _use<T>(Future<T> Function(Connection c) f) async {
    final c = await _conn();
    try {
      return await f(c);
    } catch (_) {
      if (identical(_connection, c)) _connection = null;
      unawaited(c.close().catchError((_) {}));
      rethrow;
    }
  }

  SqlTable _table(String collection) => tables[collection] ?? defaultTable;

  @override
  Future<void> open() async {
    await _conn();
  }

  @override
  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }

  @override
  Future<ChangePage> pull(
    String collection, {
    String? cursor,
    int limit = 500,
  }) async {
    final t = _table(collection);
    final stmt = _dialect.pull(collection, t, cursor, limit);
    final result = await _use(
      (c) => c.execute(stmt.sql, parameters: stmt.params),
    );
    final changes = [
      for (final row in result) _dialect.rowToChange(row.toColumnMap(), t),
    ];
    return ChangePage(
      changes: changes,
      cursor: changes.isEmpty ? null : SqlDialect.encodeCursor(changes.last),
      hasMore: changes.length == limit,
    );
  }

  @override
  bool get hasSchema => true;

  @override
  Future<CollectionSchema?> describe(String collection) async {
    final stmt = _dialect.describe(collection);
    final result = await _use(
      (c) => c.execute(stmt.sql, parameters: stmt.params),
    );
    return _dialect.schemaFrom([
      for (final row in result) row.toColumnMap(),
    ], _table(collection));
  }

  @override
  Future<bool?> canWrite(String collection) async {
    final stmt = _dialect.writePrivileges(collection);
    final result = await _use(
      (c) => c.execute(stmt.sql, parameters: stmt.params),
    );
    return result.first.toColumnMap()['ok'] == true;
  }

  /// Applies the batch in one transaction.
  @override
  Future<void> push(String collection, List<Change> changes) async {
    final t = _table(collection);
    await _use(
      (c) => c.runTx((tx) async {
        for (final c in changes) {
          final stmt = c.isDelete
              ? _dialect.delete(collection, t, c)
              : _dialect.upsert(collection, t, c);
          await tx.execute(stmt.sql, parameters: stmt.params);
        }
      }),
    );
  }
}
