import 'package:postgres/postgres.dart' as pg;

/// One table in the synced database: its rows (Postgres's estimate, kept
/// up to date by autovacuum) and what it takes up with its indexes.
typedef TableUsage = ({String name, int rows, int bytes});

/// One storage bucket: its files and their bytes.
typedef BucketUsage = ({String name, int files, int bytes});

/// The Developer view's numbers, for the whole database (every account
/// and org in it, not just this one).
typedef DatabaseStats = ({
  /// The whole database on disk: the app's tables and everything else
  /// (auth, storage's own tables, system catalogs).
  int databaseBytes,

  /// The app's tables (schema `public`), biggest first.
  List<TableUsage> tables,

  /// Files in storage, per bucket, biggest first.
  List<BucketUsage> buckets,
});

extension DatabaseTotals on DatabaseStats {
  int get rows => tables.fold(0, (n, t) => n + t.rows);
  int get tableBytes => tables.fold(0, (n, t) => n + t.bytes);
  int get files => buckets.fold(0, (n, b) => n + b.files);
  int get storageBytes => buckets.fold(0, (n, b) => n + b.bytes);
}

/// A number from the driver: Postgres sends `bigint` and `numeric` sums
/// as ints or as text, depending on the type.
int _int(Object? v) => switch (v) {
  final int n => n,
  final num n => n.round(),
  final String s => num.tryParse(s)?.round() ?? 0,
  _ => 0,
};

/// [DatabaseStats] from the queries' rows: the database's size, then
/// (name, rows, bytes) per table and (bucket, files, bytes) per bucket.
/// Each list comes out biggest first, then by name.
DatabaseStats databaseStatsFrom(
  Object? databaseBytes,
  Iterable<List<Object?>> tables,
  Iterable<List<Object?>> buckets,
) {
  int bySize(int a, int b, String x, String y) =>
      a != b ? b.compareTo(a) : x.compareTo(y);
  return (
    databaseBytes: _int(databaseBytes),
    tables: [
      for (final r in tables)
        (name: '${r[0]}', rows: _int(r[1]), bytes: _int(r[2])),
    ]..sort((a, b) => bySize(a.bytes, b.bytes, a.name, b.name)),
    buckets: [
      for (final r in buckets)
        (name: '${r[0]}', files: _int(r[1]), bytes: _int(r[2])),
    ]..sort((a, b) => bySize(a.bytes, b.bytes, a.name, b.name)),
  );
}

/// Asks the database on [connection] for its sizes. Read only.
Future<DatabaseStats> fetchDatabaseStats(pg.Connection connection) async {
  final size = await connection.execute(
    'select pg_database_size(current_database())',
  );
  final tables = await connection.execute('''
    select relname, n_live_tup, pg_total_relation_size(relid)
    from pg_stat_user_tables
    where schemaname = 'public'
  ''');
  // Supabase Storage keeps each file's size in its metadata. A database
  // without Supabase Storage has no such table: no buckets.
  final hasStorage = await connection.execute(
    "select to_regclass('storage.objects') is not null",
  );
  final buckets = hasStorage.first.first == true
      ? await connection.execute('''
          select bucket_id, count(*),
            coalesce(sum((metadata->>'size')::bigint), 0)
          from storage.objects
          group by bucket_id
        ''')
      : const <List<Object?>>[];
  return databaseStatsFrom(size.first.first, tables, buckets);
}
