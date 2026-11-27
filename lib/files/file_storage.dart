import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the app keeps its files online (card images, attachments, profile
/// photos, backgrounds), so every Mac has them. Paths are like
/// `tasks/<file>`; files never change once written (a new file gets a new
/// name), so they can be cached forever.
abstract interface class FileStorage {
  Future<void> upload(String path, List<int> bytes, {String? contentType});

  /// Null when there's no such file (not uploaded yet, or deleted).
  Future<List<int>?> download(String path);

  /// Missing ones are fine.
  Future<void> delete(List<String> paths);
}

/// Something went wrong talking to storage. [status] is the HTTP status,
/// if it got that far.
final class FileStorageException implements Exception {
  const FileStorageException(this.message, {this.status});
  final String message;
  final int? status;

  /// Bigger than the bucket allows: retrying won't help.
  bool get tooLarge => status == 413;

  @override
  String toString() => message;
}

/// How to reach a Supabase project's Storage: what's typed in Settings.
/// Kept on this Mac only (never synced), the key included.
final class StorageConfig {
  const StorageConfig({
    required this.url,
    required this.key,
    this.bucket = defaultBucket,
  });

  /// The bucket the migration creates
  /// (`supabase/migrations/*_file_storage.sql`).
  static const defaultBucket = 'files';

  /// The project URL, like `https://abcd1234.supabase.co`.
  final String url;

  /// A secret key (`sb_secret_…`, or the legacy `service_role` key). It can
  /// read and write the bucket (which is private: no one else can).
  final String key;

  final String bucket;

  /// The first thing left empty, for the button ("Enter the …").
  String? get missing => switch (this) {
    _ when url.trim().isEmpty => 'project URL',
    _ when key.trim().isEmpty => 'secret key',
    _ when bucket.trim().isEmpty => 'bucket',
    _ => null,
  };

  /// "abcd1234.supabase.co / files".
  String get description =>
      '${Uri.tryParse(_base)?.host ?? url} / ${bucket.trim()}';

  /// The URL without a trailing slash, with https:// if it was left off.
  String get _base {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u.contains('://') ? u : 'https://$u';
  }

  Map<String, Object?> toJson() => {'url': url, 'key': key, 'bucket': bucket};

  static StorageConfig? fromJson(Map<String, Object?>? json) => switch (json) {
    {'url': final String url, 'key': final String key} => StorageConfig(
      url: url,
      key: key,
      bucket: json['bucket'] as String? ?? defaultBucket,
    ),
    _ => null,
  };

  /// The project URL a Supabase pooler username (`postgres.<ref>`) points
  /// at, to fill in from the database's settings. Null for other names.
  static String? urlFromDatabaseUser(String username) =>
      switch (RegExp(r'^postgres\.([a-z0-9]+)$').firstMatch(username.trim())) {
        final m? => 'https://${m.group(1)}.supabase.co',
        null => null,
      };

  @override
  bool operator ==(Object other) =>
      other is StorageConfig &&
      other.url == url &&
      other.key == key &&
      other.bucket == bucket;

  @override
  int get hashCode => Object.hash(url, key, bucket);
}

/// [FileStorage] in a Supabase Storage bucket, through its HTTP API (served
/// through Supabase's CDN).
class SupabaseStorage implements FileStorage {
  SupabaseStorage(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final StorageConfig config;
  final http.Client _client;

  Uri _uri(List<String> segments) {
    final base = Uri.parse(config._base);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'storage',
        'v1',
        ...segments,
      ],
    );
  }

  List<String> _path(String path) => path.split('/');

  /// The key goes in `apikey`; a legacy key (a JWT) also as the bearer
  /// token, which the new `sb_secret_` keys mustn't be.
  Map<String, String> get _headers {
    final key = config.key.trim();
    return {
      'apikey': key,
      if (key.startsWith('eyJ')) 'Authorization': 'Bearer $key',
    };
  }

  @override
  Future<void> upload(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri(['object', config.bucket, ..._path(path)]),
        headers: {
          ..._headers,
          'Content-Type': contentType ?? contentTypeOf(path),
          // Replaces a half-finished earlier upload of the same file.
          'x-upsert': 'true',
          // Never changes: the CDN and Macs can keep it for a year.
          'cache-control': 'max-age=31536000',
        },
        body: bytes,
      ),
    );
    _check(response, 'upload $path');
  }

  @override
  Future<List<int>?> download(String path) async {
    final response = await _send(
      () => _client.get(
        _uri(['object', 'authenticated', config.bucket, ..._path(path)]),
        headers: _headers,
      ),
    );
    if (_notFound(response)) return null;
    _check(response, 'download $path');
    return response.bodyBytes;
  }

  @override
  Future<void> delete(List<String> paths) async {
    if (paths.isEmpty) return;
    final response = await _send(
      () => _client.delete(
        _uri(['object', config.bucket]),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'prefixes': paths}),
      ),
    );
    if (_notFound(response)) return;
    _check(response, 'delete files');
  }

  /// Writes, reads back and deletes a small file: whether the URL, key and
  /// bucket work. Throws a [FileStorageException] saying what's wrong.
  Future<void> check() async {
    const path = '.check/connection.txt';
    final probe = utf8.encode('ok ${DateTime.now().toUtc()}');
    await upload(path, probe, contentType: 'text/plain');
    final back = await download(path);
    if (back == null || utf8.decode(back) != utf8.decode(probe)) {
      throw const FileStorageException(
        'A test file was written but couldn’t be read back.',
      );
    }
    await delete([path]);
  }

  void close() => _client.close();

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 60));
    } on FileStorageException {
      rethrow;
    } catch (e) {
      throw FileStorageException('Couldn’t reach storage: $e');
    }
  }

  /// Supabase answers a missing object with 404, or 400 with a "not found"
  /// body.
  static bool _notFound(http.Response r) =>
      r.statusCode == 404 ||
      (r.statusCode == 400 && r.body.toLowerCase().contains('not_found')) ||
      (r.statusCode == 400 && r.body.toLowerCase().contains('not found'));

  static void _check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    final message = switch (r.statusCode) {
      401 || 403 => 'The secret key wasn’t accepted.',
      413 => 'The file is bigger than the bucket allows.',
      _ when r.body.contains('Bucket not found') =>
        'There’s no bucket named that. Run the storage migration first.',
      _ => 'Couldn’t $what (${r.statusCode}): ${_short(r.body)}',
    };
    throw FileStorageException(message, status: r.statusCode);
  }

  static String _short(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;
}

/// The MIME type for a file name's extension.
String contentTypeOf(String name) {
  final dot = name.lastIndexOf('.');
  return switch (dot == -1 ? '' : name.substring(dot + 1).toLowerCase()) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    'tif' || 'tiff' => 'image/tiff',
    'svg' => 'image/svg+xml',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}
