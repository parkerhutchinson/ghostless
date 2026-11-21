import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_engine/sync_engine.dart';

/// Collections the app stores locally and syncs. Add new ones here.
const syncedCollections = ['projects', 'tasks', 'profiles', 'activity'];

/// The app's data layer: everything reads and writes [store], which lives
/// on disk; [sync] (when a remote is configured) mirrors it in the
/// background.
///
/// ```dart
/// data.store.put('tasks', id, {'title': 'hi'}); // saved, works offline
/// data.store.watch('tasks');                     // UI updates from here
/// ```
class AppData {
  AppData._(this.directory, this.store, this._engine, this.sync);

  /// The app's private storage folder (database, copied images).
  final Directory directory;
  final LocalStore store;
  final SyncEngine _engine;

  /// Null when no remote is configured: the app runs local-only.
  final SyncController? sync;

  static Future<AppData> open() async {
    final dir = await getApplicationSupportDirectory();
    final store = LocalStore.open('${dir.path}/codename.db');
    final engine = SyncEngine(checkpoints: store.checkpoints)
      ..register('local', store);

    final remote = _remoteFromEnvironment();
    SyncController? sync;
    if (remote != null) {
      engine.register('remote', remote);
      sync = SyncController(
        engine: engine,
        store: store,
        pipeline: SyncPipeline(
          id: 'app',
          source: 'local',
          target: 'remote',
          direction: SyncDirection.bidirectional,
          collections: [
            for (final c in syncedCollections) CollectionMapping(c),
          ],
        ),
      )..start();
    }
    return AppData._(dir, store, engine, sync);
  }

  Future<void> close() async {
    await sync?.dispose();
    await _engine.close();
  }

  /// The remote backend, picked at build time with --dart-define, e.g.
  ///
  /// ```sh
  /// flutter run -d macos \
  ///   --dart-define=SYNC_REMOTE=sanity \
  ///   --dart-define=SANITY_PROJECT_ID=abc123 \
  ///   --dart-define=SANITY_DATASET=production \
  ///   --dart-define=SANITY_TOKEN=...
  /// ```
  ///
  /// Values passed this way are compiled into the app, so only use tokens
  /// scoped to what the app itself may do. Without SYNC_REMOTE the app
  /// runs local-only.
  static SyncAdapter? _remoteFromEnvironment() =>
      switch (const String.fromEnvironment('SYNC_REMOTE')) {
        'sanity' => SanityAdapter(
          projectId: const String.fromEnvironment('SANITY_PROJECT_ID'),
          dataset: const String.fromEnvironment(
            'SANITY_DATASET',
            defaultValue: 'production',
          ),
          token: const String.fromEnvironment('SANITY_TOKEN'),
        ),
        _ => null,
      };
}
