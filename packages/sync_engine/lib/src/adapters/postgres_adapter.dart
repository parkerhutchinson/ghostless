import 'package:postgres/postgres.dart';

import '../core/adapter.dart';
import '../core/change.dart';
import 'sql.dart';

/// Syncs Postgres tables. Collection names are table names (`schema.table`
/// works too); see [SqlTable] for what each table needs.
class PostgresAdapter implements SyncAdapter {
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

  Connection get _conn =>
      _connection ?? (throw StateError('$name is not open; call open() first'));

  SqlTable _table(String collection) => tables[collection] ?? defaultTable;

  @override
  Future<void> open() async {
    _connection ??= await Connection.open(endpoint, settings: settings);
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
    final result = await _conn.execute(stmt.sql, parameters: stmt.params);
    final changes = [
      for (final row in result) _dialect.rowToChange(row.toColumnMap(), t),
    ];
    return ChangePage(
      changes: changes,
      cursor: changes.isEmpty ? null : SqlDialect.encodeCursor(changes.last),
      hasMore: changes.length == limit,
    );
  }

  /// Applies the batch in one transaction.
  @override
  Future<void> push(String collection, List<Change> changes) async {
    final t = _table(collection);
    await _conn.runTx((tx) async {
      for (final c in changes) {
        final stmt = c.isDelete
            ? _dialect.delete(collection, t, c)
            : _dialect.upsert(collection, t, c);
        await tx.execute(stmt.sql, parameters: stmt.params);
      }
    });
  }
}
