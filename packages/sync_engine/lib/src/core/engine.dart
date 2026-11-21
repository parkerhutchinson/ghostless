import 'adapter.dart';
import 'change.dart';
import 'checkpoint_store.dart';
import 'json.dart';
import 'pipeline.dart';
import 'report.dart';

/// Moves changes between any two registered [SyncAdapter]s.
///
/// ```dart
/// final engine = SyncEngine(checkpoints: JsonFileCheckpointStore(file))
///   ..register('pg', PostgresAdapter(endpoint: ...))
///   ..register('cms', SanityAdapter(projectId: ..., dataset: ...));
/// final report = await engine.run(const SyncPipeline(
///   id: 'posts-to-cms', source: 'pg', target: 'cms',
///   collections: [CollectionMapping('posts', target: 'post')],
/// ));
/// ```
///
/// Progress is checkpointed after every successful push, so a failed or
/// interrupted run resumes where it stopped.
class SyncEngine {
  SyncEngine({CheckpointStore? checkpoints})
    : checkpoints = checkpoints ?? MemoryCheckpointStore();

  final CheckpointStore checkpoints;
  final Map<String, SyncAdapter> _adapters = {};
  final Set<String> _opened = {};
  final Set<String> _running = {};

  void register(String id, SyncAdapter adapter) {
    if (_adapters.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'An adapter is already registered');
    }
    _adapters[id] = adapter;
  }

  SyncAdapter adapter(String id) =>
      _adapters[id] ??
      (throw ArgumentError.value(id, 'id', 'No adapter registered'));

  /// Runs [pipeline] once. Errors in one collection are recorded in the
  /// report and don't stop the others.
  Future<SyncReport> run(SyncPipeline pipeline) async {
    final source = adapter(pipeline.source);
    final target = adapter(pipeline.target);
    final twoWay = pipeline.direction == SyncDirection.bidirectional;
    _require(source.capabilities.canRead, source, 'read from');
    _require(target.capabilities.canWrite, target, 'write to');
    if (twoWay) {
      _require(target.capabilities.canRead, target, 'read from');
      _require(source.capabilities.canWrite, source, 'write to');
    }
    if (!_running.add(pipeline.id)) {
      throw StateError('Pipeline "${pipeline.id}" is already running');
    }

    final report = SyncReport(pipeline.id, DateTime.now());
    try {
      await _open(pipeline.source);
      await _open(pipeline.target);
      for (final mapping in pipeline.collections) {
        final result = CollectionReport(mapping.source, mapping.target);
        report.collections.add(result);
        try {
          final ctx = _Context(pipeline, mapping, source, target, result);
          await (twoWay ? _runTwoWay(ctx) : _runOneWay(ctx));
        } catch (e, st) {
          result
            ..error = e
            ..stackTrace = st;
        }
      }
    } finally {
      _running.remove(pipeline.id);
      report.finishedAt = DateTime.now();
    }
    return report;
  }

  /// The saved cursor for one side of [mapping] in [pipeline]: how far the
  /// engine has read that side. Null before the first successful run.
  Future<String?> cursor(
    SyncPipeline pipeline,
    CollectionMapping mapping,
    Side side,
  ) => checkpoints.read(_Context.cursorKeyFor(pipeline, mapping, side));

  /// Closes every adapter this engine opened.
  Future<void> close() async {
    for (final id in _opened.toList()) {
      await _adapters[id]!.close();
      _opened.remove(id);
    }
  }

  // ---------------------------------------------------------------- one-way

  /// Streams page by page, checkpointing after each push.
  Future<void> _runOneWay(_Context ctx) async {
    final cursorKey = ctx.cursorKey(Side.source);
    var cursor = await checkpoints.read(cursorKey);
    ChangePage page;
    do {
      page = await ctx.source.pull(
        ctx.mapping.source,
        cursor: cursor,
        limit: ctx.pipeline.batchSize,
      );
      ctx.report.pulled += page.changes.length;
      final out = page.changes.map(ctx.mapToTarget).toList();
      if (out.isNotEmpty) {
        await ctx.target.push(ctx.mapping.target, out);
        ctx.report.pushedToTarget += out.length;
      }
      cursor = _advance(ctx.source, cursor, page);
      await checkpoints.write({cursorKey: cursor});
    } while (page.hasMore);
  }

  // ---------------------------------------------------------------- two-way

  /// Reads everything pending on both sides, resolves conflicts, then pushes.
  ///
  /// The engine remembers a fingerprint of every record it writes; when that
  /// write shows up in the other side's next pull it is skipped rather than
  /// echoed back.
  Future<void> _runTwoWay(_Context ctx) async {
    final (fromSource, sourceCursor) = await _drain(ctx, Side.source);
    final (fromTarget, targetCursor) = await _drain(ctx, Side.target);
    final sourcePending = await _withoutEchoes(ctx, Side.source, fromSource);
    final targetPending = await _withoutEchoes(ctx, Side.target, fromTarget);

    for (final id in sourcePending.keys.toList()) {
      final t = targetPending[id];
      if (t == null) continue;
      ctx.report.conflicts++;
      final winner = ctx.pipeline.resolveConflict(sourcePending[id]!, t);
      (winner == Side.source ? targetPending : sourcePending).remove(id);
    }

    // Source → target, then save that half's progress before the other push.
    final toTarget = sourcePending.values.map(ctx.mapToTarget).toList();
    if (toTarget.isNotEmpty) {
      await ctx.target.push(ctx.mapping.target, toTarget);
      ctx.report.pushedToTarget += toTarget.length;
    }
    await checkpoints.write({
      ctx.cursorKey(Side.source): sourceCursor,
      for (final c in sourcePending.values)
        ctx.fingerprintKey(Side.source, c.id): fingerprint(c),
      for (final c in toTarget)
        ctx.fingerprintKey(Side.target, c.id): fingerprint(c),
    });

    // Target → source.
    final toSource = targetPending.values.map(ctx.mapToSource).toList();
    if (toSource.isNotEmpty) {
      await ctx.source.push(ctx.mapping.source, toSource);
      ctx.report.pushedToSource += toSource.length;
    }
    await checkpoints.write({
      ctx.cursorKey(Side.target): targetCursor,
      for (final c in targetPending.values)
        ctx.fingerprintKey(Side.target, c.id): fingerprint(c),
      for (final c in toSource)
        ctx.fingerprintKey(Side.source, c.id): fingerprint(c),
    });
  }

  Future<(List<Change>, String?)> _drain(_Context ctx, Side side) async {
    final adapter = side == Side.source ? ctx.source : ctx.target;
    final collection = side == Side.source
        ? ctx.mapping.source
        : ctx.mapping.target;
    var cursor = await checkpoints.read(ctx.cursorKey(side));
    final changes = <Change>[];
    ChangePage page;
    do {
      page = await adapter.pull(
        collection,
        cursor: cursor,
        limit: ctx.pipeline.batchSize,
      );
      changes.addAll(page.changes);
      cursor = _advance(adapter, cursor, page);
    } while (page.hasMore);
    ctx.report.pulled += changes.length;
    return (changes, cursor);
  }

  /// Latest change per id, minus the ones that match what the engine wrote.
  Future<Map<String, Change>> _withoutEchoes(
    _Context ctx,
    Side side,
    List<Change> changes,
  ) async {
    final latest = {for (final c in changes) c.id: c};
    for (final c in latest.values.toList()) {
      final known = await checkpoints.read(ctx.fingerprintKey(side, c.id));
      if (known == fingerprint(c)) {
        latest.remove(c.id);
        ctx.report.skippedEchoes++;
      }
    }
    return latest;
  }

  String? _advance(SyncAdapter adapter, String? cursor, ChangePage page) {
    final next = page.cursor ?? cursor;
    if (page.hasMore && next == cursor) {
      throw SyncAdapterException(
        adapter.name,
        'reported more changes without advancing its cursor',
      );
    }
    return next;
  }

  Future<void> _open(String id) async {
    if (_opened.contains(id)) return;
    await _adapters[id]!.open();
    _opened.add(id);
  }

  void _require(bool ok, SyncAdapter adapter, String action) {
    if (!ok) throw StateError('Cannot $action ${adapter.name}');
  }
}

/// Per-collection state for one run.
final class _Context {
  _Context(this.pipeline, this.mapping, this.source, this.target, this.report);

  final SyncPipeline pipeline;
  final CollectionMapping mapping;
  final SyncAdapter source;
  final SyncAdapter target;
  final CollectionReport report;

  String _collection(Side side) =>
      side == Side.source ? mapping.source : mapping.target;

  String cursorKey(Side side) => cursorKeyFor(pipeline, mapping, side);

  static String cursorKeyFor(
    SyncPipeline pipeline,
    CollectionMapping mapping,
    Side side,
  ) =>
      'cursor/${pipeline.id}/${side.name}/'
      '${side == Side.source ? mapping.source : mapping.target}';

  String fingerprintKey(Side side, String id) =>
      'fp/${pipeline.id}/${side.name}/${_collection(side)}/$id';

  Change mapToTarget(Change c) => _map(c, mapping.toTarget);
  Change mapToSource(Change c) => _map(c, mapping.toSource);

  static Change _map(Change c, RecordMapper? mapper) =>
      c.isDelete || mapper == null ? c : c.withData(mapper(c.data!));
}
