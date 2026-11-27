import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sync_engine/sync_engine.dart';

import 'arriving_file.dart';
import 'file_storage.dart';

/// A file the records refer to: where it's kept online ([path], like
/// `tasks/<name>`) and on this Mac ([file]).
typedef SyncedFile = ({String path, File file});

enum FileSyncPhase { idle, syncing, offline }

final class FileSyncStatus {
  const FileSyncStatus({
    this.phase = FileSyncPhase.idle,
    this.lastSyncedAt,
    this.waiting = 0,
    this.tooLarge = 0,
    this.error,
  });

  final FileSyncPhase phase;
  final DateTime? lastSyncedAt;

  /// Files the records refer to that aren't on this Mac yet, nor online
  /// (another Mac hasn't sent them yet).
  final int waiting;

  /// Files bigger than the bucket allows: never sent.
  final int tooLarge;

  /// Why the last run stopped, when it did.
  final String? error;
}

/// Keeps the app's files (card images, attachments, profile photos,
/// backgrounds) in step with online storage: sends this Mac's files up,
/// fetches ones other Macs added, and deletes ones deleted here. Only the
/// records (file names) go through the database; the files themselves go
/// here.
///
/// Files never change once written (a changed image is a new file with a
/// new name), so each one is sent once and fetched once. What's been sent
/// is kept in the local store (collection [stateCollection], not synced).
class FileSync {
  FileSync(
    this._store, {
    required this.files,
    FileStorage Function(StorageConfig)? connectTo,
  }) : _connectTo = connectTo ?? SupabaseStorage.new;

  /// The files every record refers to, now.
  final List<SyncedFile> Function() files;

  final LocalStore _store;
  final FileStorage Function(StorageConfig) _connectTo;

  static const stateCollection = 'file_sync';
  static const _ui = 'ui', _configKey = 'storage';

  final status = ValueNotifier(const FileSyncStatus());

  FileStorage? _storage;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _debounce, _timer;
  bool _running = false, _again = false;

  /// Where files are kept, or null when they stay on this Mac.
  StorageConfig? get config =>
      StorageConfig.fromJson(_store.get(_ui, _configKey));

  /// Starts syncing if storage was connected before; then runs whenever
  /// [changes] fire (records changed: maybe new files), and every few
  /// minutes (to fetch files other Macs sent late).
  void start(List<Stream<Object?>> changes) {
    if (config case final c?) _storage = _connectTo(c);
    for (final s in changes) {
      _subscriptions.add(s.listen((_) => _schedule()));
    }
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    unawaited(syncNow());
  }

  /// Uses [config] from now on. Storage elsewhere than before starts
  /// afresh: every file is sent again.
  Future<void> connect(StorageConfig config) async {
    if (this.config != config) _clearState();
    _store.put(_ui, _configKey, config.toJson());
    _storage = _connectTo(config);
    await syncNow();
  }

  /// Files stay on this Mac only from now on. Nothing is deleted.
  void disconnect() {
    _store.delete(_ui, _configKey);
    _storage = null;
    _clearState();
    status.value = const FileSyncStatus();
  }

  /// [path] was deleted on this Mac: delete it online too (next run).
  void deleted(String path) {
    if (_storage == null) return;
    _store.put(stateCollection, path, {'delete': true});
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  /// One pass now (or right after the one running).
  Future<void> syncNow() async {
    if (_storage == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _run();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _run() async {
    final storage = _storage;
    if (storage == null) return;
    status.value = FileSyncStatus(
      phase: FileSyncPhase.syncing,
      lastSyncedAt: status.value.lastSyncedAt,
      waiting: status.value.waiting,
      tooLarge: status.value.tooLarge,
    );
    var waiting = 0, tooLarge = 0, arrived = false;
    try {
      final state = _store.all(stateCollection);
      final deletes = [
        for (final MapEntry(:key, :value) in state.entries)
          if (value['delete'] == true) key,
      ];
      if (deletes.isNotEmpty) {
        await storage.delete(deletes);
        for (final path in deletes) {
          _store.delete(stateCollection, path);
        }
      }
      for (final (:path, :file) in files()) {
        final known = state[path];
        if (known?['tooLarge'] == true) {
          tooLarge++;
          continue;
        }
        if (await file.exists()) {
          if (known?['sent'] == true) continue;
          try {
            await storage.upload(path, await file.readAsBytes());
            _mark(path, {'sent': true});
          } on FileStorageException catch (e) {
            if (!e.tooLarge) rethrow;
            _mark(path, {'tooLarge': true});
            tooLarge++;
          }
        } else {
          final bytes = await storage.download(path);
          if (bytes == null) {
            waiting++;
            continue;
          }
          await _write(file, bytes);
          _mark(path, {'sent': true});
          arrived = true;
        }
      }
      status.value = FileSyncStatus(
        lastSyncedAt: DateTime.now(),
        waiting: waiting,
        tooLarge: tooLarge,
      );
    } catch (e) {
      status.value = FileSyncStatus(
        phase: FileSyncPhase.offline,
        lastSyncedAt: status.value.lastSyncedAt,
        waiting: status.value.waiting,
        tooLarge: status.value.tooLarge,
        error: '$e',
      );
    } finally {
      // Whatever arrived shows, even if the run stopped partway.
      if (arrived) fileArrivals.value++;
    }
  }

  void _mark(String path, Map<String, Object?> value) =>
      _store.put(stateCollection, path, value);

  void _clearState() {
    for (final path in _store.all(stateCollection).keys) {
      _store.delete(stateCollection, path);
    }
  }

  /// Written beside it and then renamed into place, so a half-written
  /// file is never shown.
  static Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
  }

  void dispose() {
    _debounce?.cancel();
    _timer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    status.dispose();
  }
}
