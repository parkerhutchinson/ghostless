import 'dart:async';

import 'package:sync_engine/sync_engine.dart';

import 'app_schema.dart';
import 'compatibility.dart';
import 'remote_config.dart';

/// A live connection: where to, and the controller syncing with it.
final class SyncConnection {
  const SyncConnection(this.config, this.controller, this._adapter);
  final RemoteConfig config;
  final SyncController controller;
  final SyncAdapter _adapter;
}

/// The database the app syncs with, picked in Settings. Remembered on this
/// Mac (collection `ui`, never synced) and reconnected at launch. Without
/// one, the app runs local-only.
class SyncService {
  SyncService(
    this._store, {
    this.collections = const [],
    SyncAdapter Function(RemoteConfig, Set<String> softDeletes)? buildAdapter,
  }) : _build = buildAdapter ?? ((c, soft) => c.build(softDeletes: soft));

  /// Makes the adapter for a connection (tests swap in their own).
  final SyncAdapter Function(RemoteConfig, Set<String>) _build;

  final LocalStore _store;

  /// The collections to sync, both ways.
  final List<String> collections;

  static const _ui = 'ui', _key = 'sync';

  SyncConnection? _current;
  final _changes = StreamController<SyncConnection?>.broadcast();

  /// The current connection; null when local-only.
  SyncConnection? get current => _current;

  /// [current] now and after every connect and disconnect.
  Stream<SyncConnection?> watch() async* {
    yield _current;
    yield* _changes.stream;
  }

  /// The saved settings, connected or not (for prefilling the form).
  RemoteConfig? get saved => RemoteConfig.fromJson(
    _store.get(_ui, _key)?['config'] as Map<String, Object?>?,
  );

  /// Reconnects to the database saved last time, if any.
  void start() {
    final record = _store.get(_ui, _key);
    final config = RemoteConfig.fromJson(
      record?['config'] as Map<String, Object?>?,
    );
    if (config == null || record?['connected'] != true) return;
    _start(config, {
      ...?(record?['softDeletes'] as List?)?.whereType<String>(),
    });
  }

  /// Checks [config]'s database against the app (see
  /// [checkCompatibility]) without connecting to it.
  Future<CompatibilityReport> check(RemoteConfig config) => checkCompatibility(
    _build(config, const {}),
    jsonInText: config.storesJsonAsText,
  );

  /// Connects to [config]'s database, replacing any current connection,
  /// and starts syncing. [report] is its passing [check].
  Future<void> connect(RemoteConfig config, CompatibilityReport report) async {
    if (!report.compatible) {
      throw ArgumentError.value(report, 'report', 'is not compatible');
    }
    await _stop();
    _store.put(_ui, _key, {
      'config': config.toJson(),
      'connected': true,
      'softDeletes': report.softDeletes.toList(),
    });
    _start(config, report.softDeletes);
  }

  /// Stops syncing. Everything stays on this Mac; the settings are kept to
  /// reconnect with.
  Future<void> disconnect() async {
    await _stop();
    final record = _store.get(_ui, _key);
    if (record != null) _store.put(_ui, _key, {...record, 'connected': false});
  }

  void _start(RemoteConfig config, Set<String> softDeletes) {
    final adapter = _build(config, softDeletes);
    final engine = SyncEngine(checkpoints: _store.checkpoints)
      ..register('local', _store)
      ..register('remote', adapter);
    final controller = SyncController(
      engine: engine,
      store: _store,
      // Back within half a minute of the network returning (the default
      // waits up to 5).
      maxBackoff: const Duration(seconds: 30),
      pipeline: SyncPipeline(
        // Progress is kept per database: a different one starts afresh.
        id: 'remote/${config.identity}',
        source: 'local',
        target: 'remote',
        direction: SyncDirection.bidirectional,
        collections: [
          for (final c in collections)
            CollectionMapping(
              c,
              toTarget: config.storesJsonAsText ? toSql : null,
              // Validated on the way in: a value the app can't read is
              // dropped, so the model's default is used instead.
              toSource: (data) => withoutInvalidFields(c, fromRemote(c, data)),
            ),
        ],
      ),
    )..start();
    _current = SyncConnection(config, controller, adapter);
    _changes.add(_current);
  }

  Future<void> _stop() async {
    final current = _current;
    if (current == null) return;
    _current = null;
    _changes.add(null);
    await current.controller.dispose();
    // Not engine.close(): that would close the local store too.
    try {
      await current._adapter.close();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _stop();
    await _changes.close();
  }
}

/// When it'll try to sync again after failing: "Trying again in 8
/// seconds." (it keeps trying on its own, at most half a minute apart).
String retrying(Duration? retryIn) {
  if (retryIn == null) return 'Trying again shortly.';
  final s = retryIn.inSeconds;
  return s <= 1 ? 'Trying again in a second.' : 'Trying again in $s seconds.';
}
