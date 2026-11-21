import 'dart:convert';
import 'dart:io';

/// Where the engine keeps its progress: per-collection cursors and the
/// fingerprints it uses to recognise its own writes in two-way sync.
abstract interface class CheckpointStore {
  Future<String?> read(String key);

  /// Writes all [entries] together; a null value removes the key.
  Future<void> write(Map<String, String?> entries);
}

/// Keeps checkpoints in memory. Progress is lost when the process exits.
class MemoryCheckpointStore implements CheckpointStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(Map<String, String?> entries) async {
    entries.forEach((k, v) => v == null ? _values.remove(k) : _values[k] = v);
  }
}

/// Keeps checkpoints in a JSON file, replaced atomically on each write.
///
/// Fine for development and small datasets. Every write rewrites the whole
/// file, so for large two-way syncs store checkpoints in a database instead.
class JsonFileCheckpointStore implements CheckpointStore {
  JsonFileCheckpointStore(this.file);

  final File file;
  Map<String, String>? _values;

  Future<Map<String, String>> _load() async {
    if (_values != null) return _values!;
    if (!await file.exists()) return _values = {};
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return _values = decoded.map((k, v) => MapEntry(k, v as String));
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(Map<String, String?> entries) async {
    final values = await _load();
    entries.forEach((k, v) => v == null ? values.remove(k) : values[k] = v);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(values), flush: true);
    await tmp.rename(file.path);
  }
}
