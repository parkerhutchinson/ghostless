import 'dart:async';
import 'dart:io';

import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

/// A remote that can be taken offline.
class Remote extends MemoryAdapter {
  Remote() : super('remote');
  bool online = true;

  void _check() {
    if (!online) throw const SocketException('network is unreachable');
  }

  @override
  Future<ChangePage> pull(
    String collection, {
    String? cursor,
    int limit = 500,
  }) {
    _check();
    return super.pull(collection, cursor: cursor, limit: limit);
  }

  @override
  Future<void> push(String collection, List<Change> changes) {
    _check();
    return super.push(collection, changes);
  }
}

void main() {
  late LocalStore store;
  late Remote remote;
  late SyncEngine engine;
  late SyncController sync;

  const pipeline = SyncPipeline(
    id: 'app',
    source: 'local',
    target: 'remote',
    collections: [CollectionMapping('notes')],
    direction: SyncDirection.bidirectional,
  );

  setUp(() {
    store = LocalStore.inMemory();
    remote = Remote();
    engine = SyncEngine(checkpoints: store.checkpoints)
      ..register('local', store)
      ..register('remote', remote);
    sync = SyncController(
      engine: engine,
      store: store,
      pipeline: pipeline,
      debounce: const Duration(milliseconds: 10),
    );
  });

  tearDown(() async {
    await sync.dispose();
    await engine.close();
  });

  test('writes are readable locally right away, with no sync at all', () {
    store.put('notes', 'n1', {'text': 'hello'});
    expect(store.get('notes', 'n1'), {'text': 'hello'});
    store.delete('notes', 'n1');
    expect(store.get('notes', 'n1'), isNull);
  });

  test('putAll saves many records, and watchers hear once', () async {
    final seen = <Map<String, Map<String, Object?>>>[];
    final sub = store.watch('notes').listen(seen.add);
    await pumpEventQueue();
    store.putAll('notes', {
      'n1': {'text': 'a'},
      'n2': {'text': 'b'},
    });
    store.putAll('notes', {});
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, hasLength(2), reason: 'the first read, then one update');
    expect(seen.last.keys, ['n1', 'n2']);
    expect(store.pendingCount('notes', null), 2, reason: 'both sync out');
  });

  test('watch emits the current records and every change', () async {
    final seen = <Map<String, Map<String, Object?>>>[];
    final sub = store.watch('notes').listen(seen.add);
    await pumpEventQueue();
    store.put('notes', 'n1', {'text': 'a'});
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [
      {},
      {
        'n1': {'text': 'a'},
      },
    ]);
  });

  test(
    'offline: writes stay local and pending, then sync when back online',
    () async {
      remote.online = false;
      store.put('notes', 'n1', {'text': 'written offline'});

      await sync.syncNow();
      expect(sync.status.phase, SyncPhase.offline);
      expect(sync.status.pending, 1);
      expect(sync.status.lastError, isA<SocketException>());
      expect(store.get('notes', 'n1'), {'text': 'written offline'});
      expect(remote.records('notes'), isEmpty);

      remote.online = true;
      await sync.syncNow();
      expect(sync.status.phase, SyncPhase.idle);
      expect(sync.status.pending, 0);
      expect(remote.records('notes'), {
        'n1': {'text': 'written offline'},
      });
    },
  );

  test('a local write triggers a background sync', () async {
    sync.start();
    await sync.syncNow();
    store.put('notes', 'n1', {'text': 'auto'});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(remote.records('notes'), {
      'n1': {'text': 'auto'},
    });
  });

  test(
    'remote changes arrive in the local store and notify watchers',
    () async {
      final updates = <Map<String, Map<String, Object?>>>[];
      final sub = store.watch('notes').listen(updates.add);
      remote.put('notes', 'r1', {'text': 'from server'});

      await sync.syncNow();
      await pumpEventQueue();
      await sub.cancel();
      expect(store.get('notes', 'r1'), {'text': 'from server'});
      expect(updates.last, {
        'r1': {'text': 'from server'},
      });
      expect(
        sync.status.pending,
        0,
        reason: 'synced-in records are not pending',
      );
    },
  );

  test('a sync never overwrites a newer local write', () async {
    store.put('notes', 'n1', {'text': 'newest, local'});
    await store.push('notes', [
      Change.upsert(
        id: 'n1',
        data: {'text': 'older, remote'},
        updatedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ]);
    expect(store.get('notes', 'n1'), {'text': 'newest, local'});
  });

  test('local deletes reach the remote', () async {
    store.put('notes', 'n1', {'text': 'x'});
    await sync.syncNow();
    store.delete('notes', 'n1');
    await sync.syncNow();
    expect(remote.records('notes'), isEmpty);
  });

  test('records and sync progress survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('local_store_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/app.db';

    final first = LocalStore.open(path)..put('notes', 'n1', {'text': 'kept'});
    await first.checkpoints.write({'k': 'v'});
    await first.close();

    final reopened = LocalStore.open(path);
    expect(reopened.get('notes', 'n1'), {'text': 'kept'});
    expect(await reopened.checkpoints.read('k'), 'v');
    expect(reopened.pendingCount('notes', null), 1);
    await reopened.close();
  });
}
