import '../core/change.dart';
import '../core/schema.dart';

/// How a SQL table maps onto sync records.
///
/// Every synced table needs an id column and an updated-at timestamp that
/// changes on every write (a trigger or ORM hook usually maintains it). Use
/// a timestamp with sub-second precision — `timestamptz` in Postgres,
/// `DATETIME(6)` in MySQL — or rows written in the same second can be skipped.
///
/// Hard `DELETE`s can't be seen by polling, so deletes only propagate out of
/// a table that has a [deletedAtColumn] (soft deletes). When one is set,
/// incoming deletes set it instead of removing the row.
final class SqlTable {
  const SqlTable({
    this.idColumn = 'id',
    this.updatedAtColumn = 'updated_at',
    this.deletedAtColumn,
  });

  final String idColumn;
  final String updatedAtColumn;
  final String? deletedAtColumn;

  Set<String> get _systemColumns => {
    idColumn,
    updatedAtColumn,
    ?deletedAtColumn,
  };
}

/// A SQL string with its positional parameters.
typedef SqlStatement = ({String sql, List<Object?> params});

/// Builds the statements SQL adapters run. Kept free of any driver so it can
/// be unit-tested without a database.
abstract base class SqlDialect {
  const SqlDialect();

  /// Quotes an identifier, including `schema.table` names.
  String quote(String identifier);

  /// Placeholder for the parameter at [index] (0-based).
  String placeholder(int index);

  /// `INSERT ... ` clause that turns the insert into an upsert on the id.
  String upsertClause(SqlTable t, List<String> columns);

  /// Converts a value into something the driver accepts.
  Object? encodeValue(Object? value) => value;

  /// Rows changed after [cursor], oldest first. Ties on the timestamp are
  /// broken by id, so the cursor never skips or repeats a row.
  SqlStatement pull(String table, SqlTable t, String? cursor, int limit) {
    final u = quote(t.updatedAtColumn), i = quote(t.idColumn);
    var where = '';
    final params = <Object?>[];
    if (cursor != null) {
      final (updatedAt, id) = decodeCursor(cursor);
      where = ' WHERE ($u, $i) > (${placeholder(0)}, ${placeholder(1)})';
      params.addAll([encodeValue(updatedAt), id]);
    }
    return (
      sql: 'SELECT * FROM ${quote(table)}$where ORDER BY $u, $i LIMIT $limit',
      params: params,
    );
  }

  SqlStatement upsert(String table, SqlTable t, Change c) {
    final values = <String, Object?>{
      t.idColumn: c.id,
      t.updatedAtColumn: c.updatedAt,
      if (t.deletedAtColumn != null) t.deletedAtColumn!: null,
      for (final MapEntry(:key, :value) in c.data!.entries)
        if (!t._systemColumns.contains(key)) key: value,
    };
    final columns = values.keys.toList();
    return (
      sql:
          'INSERT INTO ${quote(table)} (${columns.map(quote).join(', ')}) '
          'VALUES (${[for (var n = 0; n < columns.length; n++) placeholder(n)].join(', ')}) '
          '${upsertClause(t, columns)}',
      params: values.values.map(encodeValue).toList(),
    );
  }

  SqlStatement delete(String table, SqlTable t, Change c) {
    final i = quote(t.idColumn);
    if (t.deletedAtColumn case final deletedAt?) {
      return (
        sql:
            'UPDATE ${quote(table)} SET ${quote(deletedAt)} = ${placeholder(0)}, '
            '${quote(t.updatedAtColumn)} = ${placeholder(1)} WHERE $i = ${placeholder(2)}',
        params: [c.updatedAt, c.updatedAt, c.id].map(encodeValue).toList(),
      );
    }
    return (
      sql: 'DELETE FROM ${quote(table)} WHERE $i = ${placeholder(0)}',
      params: [c.id],
    );
  }

  /// Turns a result row into a [Change].
  Change rowToChange(Map<String, Object?> row, SqlTable t) {
    final id = '${row[t.idColumn]}';
    final updatedAt = switch (row[t.updatedAtColumn]) {
      DateTime d => d,
      String s => DateTime.parse(s),
      final other => throw FormatException(
        'Column "${t.updatedAtColumn}" must be a timestamp, got $other',
      ),
    };
    if (t.deletedAtColumn != null && row[t.deletedAtColumn] != null) {
      return Change.delete(id: id, updatedAt: updatedAt);
    }
    return Change.upsert(
      id: id,
      updatedAt: updatedAt,
      data: {
        for (final MapEntry(:key, :value) in row.entries)
          if (!t._systemColumns.contains(key)) key: value,
      },
    );
  }

  /// The columns of [table] (`schema.table` allowed): name, type, whether
  /// it's nullable and its default. No rows when the table doesn't exist.
  SqlStatement describe(String table);

  /// How a column of SQL type [dataType] (lowercase, as
  /// `information_schema.columns.data_type` reports it) holds values.
  FieldKind kindOf(String dataType);

  /// Builds a [CollectionSchema] from [describe]'s rows (keys
  /// `column_name`, `data_type`, `is_nullable`, `column_default`, any
  /// case), checking [t]'s system columns. Null when there are no rows (no
  /// such table).
  CollectionSchema? schemaFrom(
    Iterable<Map<String, Object?>> rows,
    SqlTable t,
  ) {
    Object? value(Map<String, Object?> row, String key) =>
        row[key] ?? row[key.toUpperCase()];
    final columns = <String, FieldSchema>{};
    for (final row in rows) {
      final type = '${value(row, 'data_type')}'.toLowerCase();
      columns['${value(row, 'column_name')}'] = FieldSchema(
        kindOf(type),
        nullable: '${value(row, 'is_nullable')}'.toUpperCase() == 'YES',
        hasDefault: value(row, 'column_default') != null,
        nativeType: type,
      );
    }
    if (columns.isEmpty) return null;
    final notes = <SchemaNote>[];
    if (!columns.containsKey(t.idColumn)) {
      notes.add(
        SchemaNote(
          SchemaNoteLevel.error,
          'It has no "${t.idColumn}" column to hold record ids.',
        ),
      );
    }
    final updated = columns[t.updatedAtColumn];
    if (updated == null) {
      notes.add(
        SchemaNote(
          SchemaNoteLevel.error,
          'It has no "${t.updatedAtColumn}" column, which sync uses to find '
          'changes.',
        ),
      );
    } else if (updated.kind != FieldKind.timestamp) {
      notes.add(
        SchemaNote(
          SchemaNoteLevel.error,
          '"${t.updatedAtColumn}" is ${updated.nativeType}; it needs to be a '
          'timestamp.',
        ),
      );
    }
    if (t.deletedAtColumn case final d? when !columns.containsKey(d)) {
      notes.add(SchemaNote(SchemaNoteLevel.error, 'It has no "$d" column.'));
    }
    return CollectionSchema(
      fields: {
        for (final MapEntry(:key, :value) in columns.entries)
          if (!t._systemColumns.contains(key)) key: value,
      },
      notes: notes,
      jsonInText: true,
    );
  }

  /// Cursor = timestamp and id of the last row returned.
  static String encodeCursor(Change last) =>
      '${last.updatedAt.toUtc().toIso8601String()}|${last.id}';

  static (DateTime, String) decodeCursor(String cursor) {
    final split = cursor.indexOf('|');
    return (
      DateTime.parse(cursor.substring(0, split)),
      cursor.substring(split + 1),
    );
  }
}

final class PostgresDialect extends SqlDialect {
  const PostgresDialect();

  @override
  String quote(String identifier) => identifier
      .split('.')
      .map((p) => '"${p.replaceAll('"', '""')}"')
      .join('.');

  @override
  String placeholder(int index) => '\$${index + 1}';

  @override
  SqlStatement describe(String table) {
    final dot = table.indexOf('.');
    final schema = dot == -1 ? null : table.substring(0, dot);
    final name = dot == -1 ? table : table.substring(dot + 1);
    return (
      sql:
          'SELECT column_name, data_type, is_nullable, column_default '
          'FROM information_schema.columns '
          'WHERE table_schema = COALESCE(\$1, current_schema()) '
          'AND table_name = \$2 ORDER BY ordinal_position',
      params: [schema, name],
    );
  }

  /// Whether the current user may insert, update and delete rows in
  /// [table].
  SqlStatement writePrivileges(String table) => (
    sql:
        "SELECT has_table_privilege(\$1, 'INSERT') "
        "AND has_table_privilege(\$1, 'UPDATE') "
        "AND has_table_privilege(\$1, 'DELETE') AS ok",
    params: [quote(table)],
  );

  @override
  FieldKind kindOf(String dataType) => switch (dataType) {
    'text' || 'character varying' || 'character' || 'uuid' => FieldKind.string,
    'smallint' ||
    'integer' ||
    'bigint' ||
    'numeric' ||
    'real' ||
    'double precision' => FieldKind.number,
    'boolean' => FieldKind.boolean,
    'date' ||
    'timestamp with time zone' ||
    'timestamp without time zone' => FieldKind.timestamp,
    'json' || 'jsonb' => FieldKind.json,
    _ => FieldKind.other,
  };

  @override
  String upsertClause(SqlTable t, List<String> columns) {
    final updates = columns
        .where((c) => c != t.idColumn)
        .map((c) => '${quote(c)} = EXCLUDED.${quote(c)}');
    return 'ON CONFLICT (${quote(t.idColumn)}) DO UPDATE SET ${updates.join(', ')}';
  }
}
