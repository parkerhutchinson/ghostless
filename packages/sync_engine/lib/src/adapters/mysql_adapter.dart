import 'package:mysql1/mysql1.dart';

import '../core/adapter.dart';
import '../core/change.dart';
import '../core/json.dart';
import 'sql.dart';

/// Syncs MySQL / MariaDB tables. Collection names are table names; see
/// [SqlTable] for what each table needs.
class MySqlAdapter implements SyncAdapter {
  MySqlAdapter({
    required this.settings,
    this.tables = const {},
    this.defaultTable = const SqlTable(),
  });

  final ConnectionSettings settings;

  /// Per-table column settings; tables not listed use [defaultTable].
  final Map<String, SqlTable> tables;
  final SqlTable defaultTable;

  static const _dialect = MySqlDialect();
  MySqlConnection? _connection;

  @override
  String get name => 'mysql:${settings.host}/${settings.db}';

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities();

  MySqlConnection get _conn =>
      _connection ?? (throw StateError('$name is not open; call open() first'));

  SqlTable _table(String collection) => tables[collection] ?? defaultTable;

  @override
  Future<void> open() async {
    _connection ??= await MySqlConnection.connect(settings);
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
    final rows = await _conn.query(stmt.sql, stmt.params);
    final changes = [
      for (final row in rows)
        _dialect.rowToChange(
          // TEXT/BLOB columns come back as Blob; expose them as strings.
          row.toColumnMap().map(
            (k, v) => MapEntry(k, v is Blob ? v.toString() : v),
          ),
          t,
        ),
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
    await _conn.transaction((tx) async {
      for (final c in changes) {
        final stmt = c.isDelete
            ? _dialect.delete(collection, t, c)
            : _dialect.upsert(collection, t, c);
        await tx.query(stmt.sql, stmt.params);
      }
    });
  }
}

final class MySqlDialect extends SqlDialect {
  const MySqlDialect();

  @override
  String quote(String identifier) => identifier
      .split('.')
      .map((p) => '`${p.replaceAll('`', '``')}`')
      .join('.');

  @override
  String placeholder(int index) => '?';

  /// `VALUES(col)` works on MySQL 5.x/8.x and MariaDB alike.
  @override
  String upsertClause(SqlTable t, List<String> columns) {
    final updates = columns
        .where((c) => c != t.idColumn)
        .map((c) => '${quote(c)} = VALUES(${quote(c)})');
    return 'ON DUPLICATE KEY UPDATE ${updates.join(', ')}';
  }

  /// mysql1 requires UTC DateTimes and would expand lists into `IN` lists,
  /// so nested values go in as JSON.
  @override
  Object? encodeValue(Object? value) => switch (value) {
    DateTime() => value.toUtc(),
    Map() || List() => encodeJson(value),
    _ => value,
  };
}
