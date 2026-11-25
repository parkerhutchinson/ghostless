import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../core/adapter.dart';
import '../core/change.dart';
import '../core/checkpoint_store.dart';
import '../core/json.dart';

/// The app's on-device database, and the local side of every sync pipeline.
///
/// The app reads and writes here only — [put] and [delete] commit to disk
/// immediately, with or without a network — and a [SyncController] pushes
/// those writes to remote backends whenever it can.
///
/// Every write gets a sequence number, which is this adapter's sync cursor.
/// Rows remember whether they came from the app (`local`) or from a sync
/// (`remote`), so [pendingCount] can report unsynced app writes.
class LocalStore implements SyncAdapter {
  LocalStore._(this._db, this.name) {
    _db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('''
        CREATE TABLE IF NOT EXISTS records (
          collection TEXT NOT NULL,
          id TEXT NOT NULL,
          data TEXT,              -- JSON; NULL means deleted (a tombstone)
          updated_at TEXT NOT NULL,
          seq INTEGER NOT NULL,
          origin TEXT NOT NULL,   -- 'local' (app write) or 'remote' (sync)
          PRIMARY KEY (collection, id)
        )''')
      ..execute(
        'CREATE INDEX IF NOT EXISTS records_by_seq ON records (collection, seq)',
      )
      ..execute(
        'CREATE TABLE IF NOT EXISTS checkpoints (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
  }

  /// Opens (or creates) the database file at [path].
  factory LocalStore.open(String path) =>
      LocalStore._(sqlite3.open(path), 'local:$path');

  /// A throwaway in-memory database, for tests.
  factory LocalStore.inMemory() =>
      LocalStore._(sqlite3.openInMemory(), 'local:memory');

  final Database _db;

  @override
  final String name;

  final _changes = StreamController<String>.broadcast(sync: true);
  final _localWrites = StreamController<String>.broadcast(sync: true);

  /// Sync progress lives in the same database, so a record and the
  /// checkpoint that covers it can't disagree after a crash.
  late final CheckpointStore checkpoints = _SqliteCheckpointStore(_db);

  // ------------------------------------------------------------- app API

  Map<String, Object?>? get(String collection, String id) {
    final rows = _db.select(
      'SELECT data FROM records WHERE collection = ? AND id = ? AND data IS NOT NULL',
      [collection, id],
    );
    return rows.isEmpty ? null : _decode(rows.first['data'] as String);
  }

  /// All live records in [collection], by id.
  Map<String, Map<String, Object?>> all(String collection) => {
    for (final row in _db.select(
      'SELECT id, data FROM records WHERE collection = ? AND data IS NOT NULL ORDER BY id',
      [collection],
    ))
      row['id'] as String: _decode(row['data'] as String),
  };

  /// Saves a record locally. Returns once it is on disk.
  void put(String collection, String id, Map<String, Object?> data) {
    _write(
      collection,
      Change.upsert(id: id, data: data, updatedAt: _now()),
      'local',
    );
    _localWrites.add(collection);
  }

  /// Saves several records in [collection] at once: one transaction, and
  /// watchers hear about it once (not once per record, which re-reads the
  /// whole collection each time).
  void putAll(String collection, Map<String, Map<String, Object?>> records) {
    if (records.isEmpty) return;
    final now = _now();
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final MapEntry(key: id, value: data) in records.entries) {
        _write(
          collection,
          Change.upsert(id: id, data: data, updatedAt: now),
          'local',
          notify: false,
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _changes.add(collection);
    _localWrites.add(collection);
  }

  /// Deletes a record locally (kept as a tombstone so the delete can sync).
  void delete(String collection, String id) {
    _write(collection, Change.delete(id: id, updatedAt: _now()), 'local');
    _localWrites.add(collection);
  }

  /// Emits [all] for [collection] now and after every change to it, whether
  /// the app made it or a sync brought it in.
  Stream<Map<String, Map<String, Object?>>> watch(String collection) async* {
    yield all(collection);
    yield* _changes.stream
        .where((c) => c == collection)
        .map((_) => all(collection));
  }

  /// Fires with the collection name after each app write (not sync writes).
  Stream<String> get localWrites => _localWrites.stream;

  /// App writes in [collection] newer than [cursor] — i.e. not yet synced.
  int pendingCount(String collection, String? cursor) =>
      _db.select(
            "SELECT count(*) AS n FROM records WHERE collection = ? AND origin = 'local' AND seq > ?",
            [collection, cursor == null ? 0 : int.parse(cursor)],
          ).first['n']
          as int;

  // ----------------------------------------------------------- SyncAdapter

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities();

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {
    await _changes.close();
    await _localWrites.close();
    _db.close();
  }

  @override
  Future<ChangePage> pull(
    String collection, {
    String? cursor,
    int limit = 500,
  }) async {
    final rows = _db.select(
      'SELECT id, data, updated_at, seq FROM records '
      'WHERE collection = ? AND seq > ? ORDER BY seq LIMIT ?',
      [collection, cursor == null ? 0 : int.parse(cursor), limit + 1],
    );
    final page = rows.take(limit).toList();
    return ChangePage(
      changes: [
        for (final row in page)
          row['data'] == null
              ? Change.delete(
                  id: row['id'] as String,
                  updatedAt: DateTime.parse(row['updated_at'] as String),
                )
              : Change.upsert(
                  id: row['id'] as String,
                  updatedAt: DateTime.parse(row['updated_at'] as String),
                  data: _decode(row['data'] as String),
                ),
      ],
      cursor: page.isEmpty ? null : '${page.last['seq']}',
      hasMore: rows.length > limit,
    );
  }

  /// Applies changes from a remote, in one transaction.
  ///
  /// An incoming change never overwrites a newer app write: that write was
  /// made after the sync read this store, and goes out on the next sync.
  @override
  Future<void> push(String collection, List<Change> changes) async {
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final c in changes) {
        final existing = _db.select(
          'SELECT updated_at, origin FROM records WHERE collection = ? AND id = ?',
          [collection, c.id],
        );
        final newerLocal =
            existing.isNotEmpty &&
            existing.first['origin'] == 'local' &&
            DateTime.parse(existing.first['updated_at'] as String)
                .isAfter(c.updatedAt);
        if (!newerLocal) _write(collection, c, 'remote', notify: false);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    if (changes.isNotEmpty) _changes.add(collection);
  }

  // ------------------------------------------------------------- internals

  void _write(
    String collection,
    Change c,
    String origin, {
    bool notify = true,
  }) {
    _db.execute(
      '''
      INSERT INTO records (collection, id, data, updated_at, seq, origin)
      VALUES (?, ?, ?, ?, (SELECT coalesce(max(seq), 0) + 1 FROM records), ?)
      ON CONFLICT (collection, id) DO UPDATE SET
        data = excluded.data, updated_at = excluded.updated_at,
        seq = excluded.seq, origin = excluded.origin''',
      [
        collection,
        c.id,
        c.isDelete ? null : encodeJson(c.data),
        c.updatedAt.toUtc().toIso8601String(),
        origin,
      ],
    );
    if (notify) _changes.add(collection);
  }

  static DateTime _now() => DateTime.now().toUtc();

  static Map<String, Object?> _decode(String json) =>
      (jsonDecode(json) as Map).cast<String, Object?>();
}

final class _SqliteCheckpointStore implements CheckpointStore {
  _SqliteCheckpointStore(this._db);
  final Database _db;

  @override
  Future<String?> read(String key) async {
    final rows = _db.select('SELECT value FROM checkpoints WHERE key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> write(Map<String, String?> entries) async {
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final MapEntry(:key, :value) in entries.entries) {
        if (value == null) {
          _db.execute('DELETE FROM checkpoints WHERE key = ?', [key]);
        } else {
          _db.execute(
            'INSERT INTO checkpoints (key, value) VALUES (?, ?) '
            'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
            [key, value],
          );
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
