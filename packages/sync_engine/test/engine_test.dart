import 'dart:io';

import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

DateTime t(int minute) => DateTime.utc(2026, 1, 1, 0, minute);

/// Memory adapter whose next push can be made to fail.
class FlakyAdapter extends MemoryAdapter {
  FlakyAdapter() : super('flaky');
  bool failNextPush = false;

  @override
  Future<void> push(String collection, List<Change> changes) async {
    if (failNextPush) {
      failNextPush = false;
      throw SyncAdapterException(name, 'simulated outage');
    }
    return super.push(collection, changes);
  }
}

class ReadOnlyAdapter extends MemoryAdapter {
  @override
  AdapterCapabilities get capabilities =>
      const AdapterCapabilities(canWrite: false);
}

void main() {
  late MemoryAdapter a;
  late MemoryAdapter b;
  late SyncEngine engine;

  setUp(() {
    a = MemoryAdapter('a');
    b = MemoryAdapter('b');
    engine = SyncEngine()
      ..register('a', a)
      ..register('b', b);
  });

  group('one-way', () {
    const pipeline = SyncPipeline(
      id: 'p',
      source: 'a',
      target: 'b',
      collections: [CollectionMapping('posts')],
      batchSize: 2,
    );

    test('copies records across several pages', () async {
      for (var i = 0; i < 5; i++) {
        a.put('posts', '$i', {'title': 'Post $i'});
      }
      final report = await engine.run(pipeline);
      expect(report.ok, isTrue, reason: '$report');
      expect(b.records('posts'), hasLength(5));
      expect(b.records('posts')['3'], {'title': 'Post 3'});
      expect(report.collections.single.pushedToTarget, 5);
    });

    test('only sends new changes on the next run, including deletes', () async {
      a.put('posts', '1', {'title': 'one'});
      a.put('posts', '2', {'title': 'two'});
      await engine.run(pipeline);

      a.put('posts', '1', {'title': 'one, edited'});
      a.remove('posts', '2');
      final report = await engine.run(pipeline);

      expect(report.collections.single.pulled, 2);
      expect(b.records('posts'), {
        '1': {'title': 'one, edited'},
      });
    });

    test('maps collection names and fields', () async {
      a.put('posts', '1', {'title': 'Hello'});
      await engine.run(
        SyncPipeline(
          id: 'mapped',
          source: 'a',
          target: 'b',
          collections: [
            CollectionMapping(
              'posts',
              target: 'article',
              toTarget: (d) => {'headline': d['title']},
            ),
          ],
        ),
      );
      expect(b.records('article'), {
        '1': {'headline': 'Hello'},
      });
    });

    test('a failed push keeps the cursor so the next run retries', () async {
      final flaky = FlakyAdapter()..failNextPush = true;
      engine.register('flaky', flaky);
      a.put('posts', '1', {'title': 'one'});
      const toFlaky = SyncPipeline(
        id: 'f',
        source: 'a',
        target: 'flaky',
        collections: [CollectionMapping('posts')],
      );

      final failed = await engine.run(toFlaky);
      expect(failed.ok, isFalse);
      expect(failed.collections.single.error, isA<SyncAdapterException>());

      final retried = await engine.run(toFlaky);
      expect(retried.ok, isTrue);
      expect(flaky.records('posts'), hasLength(1));
    });

    test('refuses a target that cannot be written', () async {
      engine.register('ro', ReadOnlyAdapter());
      expect(
        () => engine.run(
          const SyncPipeline(
            id: 'x',
            source: 'a',
            target: 'ro',
            collections: [CollectionMapping('posts')],
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('two-way', () {
    SyncPipeline twoWay({
      ConflictResolver resolve = ConflictResolvers.lastWriteWins,
    }) => SyncPipeline(
      id: 'tw',
      source: 'a',
      target: 'b',
      collections: const [CollectionMapping('posts')],
      direction: SyncDirection.bidirectional,
      resolveConflict: resolve,
    );

    test('changes on either side reach the other', () async {
      a.put('posts', 'from-a', {'title': 'A'});
      b.put('posts', 'from-b', {'title': 'B'});
      final report = await engine.run(twoWay());
      expect(report.ok, isTrue, reason: '$report');
      expect(a.records('posts').keys, unorderedEquals(['from-a', 'from-b']));
      expect(b.records('posts').keys, unorderedEquals(['from-a', 'from-b']));
    });

    test("doesn't echo its own writes back", () async {
      a.put('posts', '1', {'title': 'A'});
      b.put('posts', '2', {'title': 'B'});
      await engine.run(twoWay());

      final second = (await engine.run(twoWay())).collections.single;
      expect(second.pushedToTarget, 0);
      expect(second.pushedToSource, 0);
      expect(second.skippedEchoes, 2);
    });

    test('last write wins a conflict', () async {
      a.put('posts', '1', {'title': 'original'}, at: t(0));
      await engine.run(twoWay());

      a.put('posts', '1', {'title': 'edited in A'}, at: t(5));
      b.put('posts', '1', {'title': 'edited in B'}, at: t(9));
      final report = (await engine.run(twoWay())).collections.single;

      expect(report.conflicts, 1);
      expect(a.records('posts')['1'], {'title': 'edited in B'});
      expect(b.records('posts')['1'], {'title': 'edited in B'});
    });

    test('a custom resolver can make the source win', () async {
      a.put('posts', '1', {'title': 'A'}, at: t(1));
      b.put('posts', '1', {'title': 'B'}, at: t(9));
      await engine.run(twoWay(resolve: ConflictResolvers.sourceWins));
      expect(b.records('posts')['1'], {'title': 'A'});
    });

    test('deletes propagate both ways', () async {
      a.put('posts', '1', {'title': 'one'});
      a.put('posts', '2', {'title': 'two'});
      await engine.run(twoWay());

      a.remove('posts', '1');
      b.remove('posts', '2');
      await engine.run(twoWay());
      expect(a.records('posts'), isEmpty);
      expect(b.records('posts'), isEmpty);
    });
  });

  test('JsonFileCheckpointStore persists across instances', () async {
    final dir = await Directory.systemTemp.createTemp('sync_engine_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/checkpoints.json');

    await JsonFileCheckpointStore(file).write({'cursor': '42', 'gone': null});
    final reopened = JsonFileCheckpointStore(file);
    expect(await reopened.read('cursor'), '42');
    await reopened.write({'cursor': null});
    expect(await JsonFileCheckpointStore(file).read('cursor'), isNull);
  });

  test('fingerprint ignores key order', () {
    final now = DateTime.now();
    expect(
      fingerprint(
        Change.upsert(
          id: '1',
          data: {
            'a': 1,
            'b': {'x': 1, 'y': 2},
          },
          updatedAt: now,
        ),
      ),
      fingerprint(
        Change.upsert(
          id: '1',
          data: {
            'b': {'y': 2, 'x': 1},
            'a': 1,
          },
          updatedAt: now,
        ),
      ),
    );
  });
}
