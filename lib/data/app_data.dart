import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_engine/sync_engine.dart';

import '../sync/app_schema.dart';
import '../sync/sync_service.dart';

/// Collections the app stores locally and syncs (see [appSchema], which
/// lists their fields). Add new ones there.
final syncedCollections = appSchema.keys.toList();

/// The app's data layer: everything reads and writes [store], which lives
/// on disk; [sync] mirrors it with the database picked in Settings (if
/// any) in the background.
///
/// ```dart
/// data.store.put('tasks', id, {'title': 'hi'}); // saved, works offline
/// data.store.watch('tasks');                     // UI updates from here
/// ```
class AppData {
  AppData._(this.directory, this.store, this.sync);

  /// The app's private storage folder (database, copied images).
  final Directory directory;
  final LocalStore store;

  /// Connects to a database from Settings; local-only until then.
  final SyncService sync;

  static Future<AppData> open() async {
    final dir = await getApplicationSupportDirectory();
    final store = LocalStore.open('${dir.path}/codename.db');
    final sync = SyncService(store, collections: syncedCollections)..start();
    return AppData._(dir, store, sync);
  }

  Future<void> close() async {
    await sync.dispose();
    await store.close();
  }
}
