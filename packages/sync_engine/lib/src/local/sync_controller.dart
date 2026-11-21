import 'dart:async';
import 'dart:math';

import '../core/engine.dart';
import '../core/pipeline.dart';
import '../core/report.dart';
import 'local_store.dart';

enum SyncPhase {
  /// Last sync succeeded; waiting for the next trigger.
  idle,

  /// A sync is running.
  syncing,

  /// The last sync failed (usually no network); retrying with backoff.
  /// Local reads and writes keep working.
  offline,
}

final class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.pending = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final SyncPhase phase;

  /// Local writes not yet pushed to the remote.
  final int pending;
  final DateTime? lastSyncedAt;
  final Object? lastError;

  @override
  String toString() =>
      'SyncStatus(${phase.name}, pending: $pending'
      '${lastError == null ? '' : ', error: $lastError'})';
}

/// Keeps a [LocalStore] in sync with a remote, in the background.
///
/// The app never waits on this: it writes to the store, and the controller
/// syncs shortly after each write ([debounce]), every [interval], and on
/// demand via [syncNow]. When a sync fails it retries with exponential
/// backoff up to [maxBackoff], and nothing is lost meanwhile — unsynced
/// writes stay in the store until a sync succeeds.
///
/// [pipeline] must be bidirectional with the store registered as its source.
class SyncController {
  SyncController({
    required this.engine,
    required this.store,
    required this.pipeline,
    this.debounce = const Duration(seconds: 2),
    this.interval = const Duration(minutes: 1),
    this.maxBackoff = const Duration(minutes: 5),
  }) {
    if (pipeline.direction != SyncDirection.bidirectional ||
        !identical(engine.adapter(pipeline.source), store)) {
      throw ArgumentError(
        'pipeline must be bidirectional with the LocalStore as its source',
      );
    }
  }

  final SyncEngine engine;
  final LocalStore store;
  final SyncPipeline pipeline;
  final Duration debounce;
  final Duration interval;
  final Duration maxBackoff;

  final _status = StreamController<SyncStatus>.broadcast();
  SyncStatus _current = const SyncStatus(phase: SyncPhase.idle);
  StreamSubscription<String>? _writes;
  Timer? _debounceTimer;
  Timer? _intervalTimer;
  Timer? _retryTimer;
  Future<SyncReport?>? _inFlight;
  bool _rerun = false;
  int _failures = 0;
  bool _disposed = false;

  SyncStatus get status => _current;

  /// The current status, then every change to it.
  Stream<SyncStatus> get statusStream async* {
    yield _current;
    yield* _status.stream;
  }

  /// Starts background syncing and runs a first sync.
  void start() {
    _writes ??= store.localWrites.listen((_) {
      unawaited(_refreshPending());
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, syncNow);
    });
    _intervalTimer ??= Timer.periodic(interval, (_) => syncNow());
    unawaited(syncNow());
  }

  /// Syncs now. If a sync is already running, another runs right after it
  /// (so writes made during the first aren't left waiting).
  Future<SyncReport?> syncNow() {
    if (_disposed) return Future.value();
    if (_inFlight != null) {
      _rerun = true;
      return _inFlight!;
    }
    return _inFlight = _run().whenComplete(() {
      _inFlight = null;
      if (_rerun && !_disposed) {
        _rerun = false;
        unawaited(syncNow());
      }
    });
  }

  Future<SyncReport?> _run() async {
    _retryTimer?.cancel();
    _emit(
      SyncStatus(
        phase: SyncPhase.syncing,
        pending: _current.pending,
        lastSyncedAt: _current.lastSyncedAt,
      ),
    );
    try {
      final report = await engine.run(pipeline);
      if (!report.ok) {
        throw report.collections.firstWhere((c) => !c.ok).error!;
      }
      _failures = 0;
      _emit(
        SyncStatus(
          phase: SyncPhase.idle,
          pending: await _pending(),
          lastSyncedAt: DateTime.now(),
        ),
      );
      return report;
    } catch (e) {
      _failures++;
      final delay = Duration(
        milliseconds: min(
          maxBackoff.inMilliseconds,
          1000 * pow(2, min(_failures, 16)).toInt(),
        ),
      );
      if (!_disposed) _retryTimer = Timer(delay, syncNow);
      _emit(
        SyncStatus(
          phase: SyncPhase.offline,
          pending: await _pending(),
          lastSyncedAt: _current.lastSyncedAt,
          lastError: e,
        ),
      );
      return null;
    }
  }

  Future<int> _pending() async {
    var total = 0;
    for (final mapping in pipeline.collections) {
      final cursor = await engine.cursor(pipeline, mapping, Side.source);
      total += store.pendingCount(mapping.source, cursor);
    }
    return total;
  }

  Future<void> _refreshPending() async {
    final pending = await _pending();
    if (pending != _current.pending) {
      _emit(
        SyncStatus(
          phase: _current.phase,
          pending: pending,
          lastSyncedAt: _current.lastSyncedAt,
          lastError: _current.lastError,
        ),
      );
    }
  }

  void _emit(SyncStatus status) {
    if (_disposed) return;
    _current = status;
    _status.add(status);
  }

  /// Stops background syncing. Doesn't close the store or engine.
  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _intervalTimer?.cancel();
    _retryTimer?.cancel();
    await _writes?.cancel();
    await _inFlight;
    await _status.close();
  }
}
