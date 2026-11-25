import 'dart:convert';
import 'dart:io';

import 'package:codename/files/arriving_file.dart';
import 'package:codename/files/file_storage.dart';
import 'package:codename/files/file_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/sync_engine.dart';

/// Storage in memory, failing on request.
class FakeStorage implements FileStorage {
  final files = <String, List<int>>{};
  final uploads = <String>[];
  final deletes = <String>[];
  int maxSize = 1 << 30;
  bool offline = false;

  @override
  Future<void> upload(
    String path,
    List<int> bytes, {
    String? contentType,
  }) async {
    if (offline) throw const FileStorageException('offline');
    if (bytes.length > maxSize) {
      throw const FileStorageException('too big', status: 413);
    }
    uploads.add(path);
    files[path] = bytes;
  }

  @override
  Future<List<int>?> download(String path) async {
    if (offline) throw const FileStorageException('offline');
    return files[path];
  }

  @override
  Future<void> delete(List<String> paths) async {
    if (offline) throw const FileStorageException('offline');
    deletes.addAll(paths);
    paths.forEach(files.remove);
  }
}

void main() {
  late Directory dir;
  late LocalStore store;
  late FakeStorage storage;
  late List<SyncedFile> wanted;
  late FileSync sync;
  const config = StorageConfig(url: 'https://abc.supabase.co', key: 'k');

  File local(String name) => File('${dir.path}/$name');

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('file_sync_test');
    store = LocalStore.inMemory();
    storage = FakeStorage();
    wanted = [];
    sync = FileSync(store, files: () => wanted, connectTo: (_) => storage);
    sync.start(const []);
    await sync.connect(config);
  });

  tearDown(() async {
    sync.dispose();
    await store.close();
    dir.deleteSync(recursive: true);
  });

  test("sends this Mac's files once", () async {
    local('a.jpg').writeAsBytesSync([1, 2, 3]);
    wanted = [(path: 'tasks/a.jpg', file: local('a.jpg'))];
    await sync.syncNow();
    expect(storage.files['tasks/a.jpg'], [1, 2, 3]);
    await sync.syncNow();
    expect(storage.uploads, ['tasks/a.jpg'], reason: 'not sent again');
    expect(sync.status.value.phase, FileSyncPhase.idle);
  });

  test("fetches other Macs' files, and says when they arrive", () async {
    storage.files['profiles/p.png'] = [9, 9];
    wanted = [(path: 'profiles/p.png', file: local('sub/p.png'))];
    final before = fileArrivals.value;
    await sync.syncNow();
    expect(local('sub/p.png').readAsBytesSync(), [9, 9]);
    expect(fileArrivals.value, before + 1);
    expect(storage.uploads, isEmpty, reason: 'came from there');
    expect(local('sub/p.png.part').existsSync(), isFalse);
  });

  test('a file not sent yet by another Mac waits', () async {
    wanted = [(path: 'tasks/later.jpg', file: local('later.jpg'))];
    await sync.syncNow();
    expect(sync.status.value.waiting, 1);
    storage.files['tasks/later.jpg'] = [4];
    await sync.syncNow();
    expect(sync.status.value.waiting, 0);
    expect(local('later.jpg').existsSync(), isTrue);
  });

  test('deleted here: deleted there', () async {
    storage.files['tasks/old.jpg'] = [1];
    sync.deleted('tasks/old.jpg');
    await sync.syncNow();
    expect(storage.deletes, ['tasks/old.jpg']);
    expect(storage.files, isEmpty);
    await sync.syncNow();
    expect(storage.deletes, hasLength(1), reason: 'only once');
  });

  test('too big: counted, never retried', () async {
    storage.maxSize = 2;
    local('big.pdf').writeAsBytesSync([1, 2, 3, 4]);
    wanted = [(path: 'tasks/big.pdf', file: local('big.pdf'))];
    await sync.syncNow();
    await sync.syncNow();
    expect(storage.files, isEmpty);
    expect(sync.status.value.tooLarge, 1);
    expect(sync.status.value.phase, FileSyncPhase.idle);
  });

  test('offline: says so, and sends it once back', () async {
    storage.offline = true;
    local('a.jpg').writeAsBytesSync([1]);
    wanted = [(path: 'tasks/a.jpg', file: local('a.jpg'))];
    await sync.syncNow();
    expect(sync.status.value.phase, FileSyncPhase.offline);
    expect(sync.status.value.error, 'offline');
    storage.offline = false;
    await sync.syncNow();
    expect(storage.files.keys, ['tasks/a.jpg']);
    expect(sync.status.value.phase, FileSyncPhase.idle);
  });

  test('other storage: everything is sent again; disconnect forgets', () async {
    local('a.jpg').writeAsBytesSync([1]);
    wanted = [(path: 'tasks/a.jpg', file: local('a.jpg'))];
    await sync.syncNow();
    await sync.connect(
      const StorageConfig(url: 'https://other.supabase.co', key: 'k'),
    );
    expect(storage.uploads, ['tasks/a.jpg', 'tasks/a.jpg']);
    sync.disconnect();
    expect(sync.config, isNull);
    expect(store.all(FileSync.stateCollection), isEmpty);
  });

  group('StorageConfig', () {
    test('missing, description, JSON', () {
      expect(const StorageConfig(url: '', key: 'k').missing, 'project URL');
      expect(const StorageConfig(url: 'u', key: ' ').missing, 'secret key');
      expect(config.missing, isNull);
      expect(config.description, 'abc.supabase.co / files');
      expect(StorageConfig.fromJson(config.toJson()), config);
      expect(StorageConfig.fromJson(null), isNull);
    });

    test('the project URL from a Supabase pooler username', () {
      expect(
        StorageConfig.urlFromDatabaseUser('postgres.abcd1234'),
        'https://abcd1234.supabase.co',
      );
      expect(StorageConfig.urlFromDatabaseUser('postgres'), isNull);
      expect(StorageConfig.urlFromDatabaseUser('someone.else'), isNull);
    });
  });

  group('SupabaseStorage', () {
    SupabaseStorage client(
      String key,
      http.Response Function(http.Request) handle,
    ) => SupabaseStorage(
      StorageConfig(url: 'abc.supabase.co/', key: key),
      client: MockClient((r) async => handle(r)),
    );

    test('uploads to the bucket, with the key the right way', () async {
      late http.Request sent;
      await client('sb_secret_x', (r) {
        sent = r;
        return http.Response('{}', 200);
      }).upload('tasks/a b.jpg', [1, 2]);
      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'https://abc.supabase.co/storage/v1/object/files/tasks/a%20b.jpg',
      );
      expect(sent.headers['apikey'], 'sb_secret_x');
      expect(sent.headers.containsKey('Authorization'), isFalse);
      expect(sent.headers['Content-Type'], 'image/jpeg');
      expect(sent.headers['x-upsert'], 'true');
      expect(sent.bodyBytes, [1, 2]);

      await client('eyJlegacy', (r) {
        sent = r;
        return http.Response('{}', 200);
      }).upload('tasks/b.png', [1]);
      expect(sent.headers['Authorization'], 'Bearer eyJlegacy');
    });

    test('a missing file downloads as null; errors say why', () async {
      expect(
        await client(
          'k',
          (_) => http.Response('{"statusCode":"404","error":"not_found"}', 400),
        ).download('tasks/x.jpg'),
        isNull,
      );
      expect(
        await client(
          'k',
          (_) => http.Response.bytes([7], 200),
        ).download('tasks/x.jpg'),
        [7],
      );
      expect(
        () => client('k', (_) => http.Response('no', 403)).download('x'),
        throwsA(
          isA<FileStorageException>().having(
            (e) => e.message,
            'message',
            contains('secret key'),
          ),
        ),
      );
      expect(
        () => client('k', (_) => http.Response('big', 413)).upload('x', [1]),
        throwsA(
          isA<FileStorageException>().having(
            (e) => e.tooLarge,
            'tooLarge',
            true,
          ),
        ),
      );
    });

    test('deletes by prefixes', () async {
      late http.Request sent;
      await client('k', (r) {
        sent = r;
        return http.Response('[]', 200);
      }).delete(['tasks/a.jpg', 'profiles/b.png']);
      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/storage/v1/object/files');
      expect(jsonDecode(sent.body), {
        'prefixes': ['tasks/a.jpg', 'profiles/b.png'],
      });
    });
  });

  test('contentTypeOf', () {
    expect(contentTypeOf('a.PDF'), 'application/pdf');
    expect(contentTypeOf('a.jpeg'), 'image/jpeg');
    expect(contentTypeOf('noext'), 'application/octet-stream');
  });
}
