import '../core/adapter.dart';
import '../core/change.dart';

/// Stores records in memory. Useful for tests, prototypes and as a local cache.
///
/// Every write gets a sequence number, which is the cursor, so pulls are exact.
class MemoryAdapter implements SyncAdapter {
  MemoryAdapter([this.name = 'memory']);

  @override
  final String name;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities();

  final Map<String, Map<String, _Row>> _collections = {};
  int _seq = 0;

  /// Current (non-deleted) records in [collection], by id.
  Map<String, Map<String, Object?>> records(String collection) => {
    for (final MapEntry(:key, :value)
        in (_collections[collection] ?? {}).entries)
      if (!value.deleted) key: value.data!,
  };

  /// Writes a record directly, as a user of this backend would.
  void put(
    String collection,
    String id,
    Map<String, Object?> data, {
    DateTime? at,
  }) => _apply(
    collection,
    Change.upsert(id: id, data: data, updatedAt: at ?? DateTime.now()),
  );

  /// Deletes a record directly, as a user of this backend would.
  void remove(String collection, String id, {DateTime? at}) => _apply(
    collection,
    Change.delete(id: id, updatedAt: at ?? DateTime.now()),
  );

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<ChangePage> pull(
    String collection, {
    String? cursor,
    int limit = 500,
  }) async {
    final after = cursor == null ? 0 : int.parse(cursor);
    final rows =
        (_collections[collection]?.values ?? const <_Row>[])
            .where((r) => r.seq > after)
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    final page = rows.take(limit).toList();
    return ChangePage(
      changes: [
        for (final r in page)
          r.deleted
              ? Change.delete(id: r.id, updatedAt: r.updatedAt)
              : Change.upsert(id: r.id, data: r.data!, updatedAt: r.updatedAt),
      ],
      cursor: page.isEmpty ? null : '${page.last.seq}',
      hasMore: rows.length > limit,
    );
  }

  @override
  Future<void> push(String collection, List<Change> changes) async {
    for (final c in changes) {
      _apply(collection, c);
    }
  }

  void _apply(String collection, Change c) {
    (_collections[collection] ??= {})[c.id] = _Row(
      c.id,
      c.isDelete ? null : Map.of(c.data!),
      c.updatedAt,
      ++_seq,
    );
  }
}

final class _Row {
  _Row(this.id, this.data, this.updatedAt, this.seq);
  final String id;
  final Map<String, Object?>? data;
  final DateTime updatedAt;
  final int seq;
  bool get deleted => data == null;
}
