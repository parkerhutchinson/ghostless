import 'package:codename/activity/activity.dart';
import 'package:codename/profiles/profile.dart';
import 'package:codename/projects/project.dart';
import 'package:codename/sync/app_schema.dart';
import 'package:codename/sync/compatibility.dart';
import 'package:codename/sync/remote_config.dart';
import 'package:codename/sync/sync_service.dart';
import 'package:codename/comments/comment.dart';
import 'package:codename/tasks/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

/// A database with a schema: [MemoryAdapter] for the records, plus
/// structure and permissions as given.
class FakeDatabase extends MemoryAdapter implements SchemaInspector {
  FakeDatabase({this.schemas = const {}, this.writable = true});

  final Map<String, CollectionSchema> schemas;
  final bool writable;

  @override
  bool get hasSchema => true;

  @override
  Future<CollectionSchema?> describe(String collection) async =>
      schemas[collection];

  @override
  Future<bool?> canWrite(String collection) async => writable;
}

/// A schema with exactly the app's fields, each in a matching JSON column.
Map<String, CollectionSchema> matchingSchemas() => {
  for (final MapEntry(key: c, value: fields) in appSchema.entries)
    c: CollectionSchema(
      fields: {
        for (final MapEntry(:key, :value) in fields.entries)
          key: FieldSchema(switch (value) {
            ValueKind.string || ValueKind.timestamp => FieldKind.string,
            ValueKind.number => FieldKind.number,
            _ => FieldKind.json,
          }, nativeType: 'jsonb'),
      },
    ),
};

void main() {
  final at = DateTime.utc(2026, 11, 21);

  test('the app schema matches what the models store', () {
    final samples = {
      'projects': Project(
        id: 'p',
        name: 'Website',
        ownerId: 'me',
        createdAt: at,
      ).toJson(),
      'tasks': Task(
        id: 't',
        title: 'Ship',
        originId: 'p',
        projectIds: const ['p', 'q'],
        tags: const ['x'],
        dueDate: DateTime(2026, 12, 1),
        dueTime: 600,
        placements: const {'q': (status: 'todo', order: 1)},
        completedIn: const {'p'},
        subtasks: const [Subtask(id: 's', title: 'Step')],
        assigneeId: 'me',
        createdAt: at,
      ).toJson(),
      'profiles': Profile(
        id: 'me',
        name: 'Ada',
        imageFile: 'a.png',
        personalProjectId: 'p',
        theme: const {'accent': 1},
        createdAt: at,
      ).toJson(),
      'activity': Activity(
        id: 'a',
        recipientId: 'me',
        actorId: 'you',
        taskId: 't',
        taskTitle: 'Ship',
        kind: ActivityKind.updated,
        changes: const [TaskChange.due],
        dueAt: at,
        createdAt: at,
        readAt: at,
        excerpt: 'Looks good',
      ).toJson(),
      'comments': Comment(
        id: 'c',
        taskId: 't',
        authorId: 'me',
        body: 'Looks **good**',
        createdAt: at,
      ).toJson(),
    };
    expect(samples.keys, unorderedEquals(appSchema.keys));
    for (final MapEntry(key: c, value: json) in samples.entries) {
      expect(json.keys, unorderedEquals(appSchema[c]!.keys), reason: c);
      expect(invalidFields(c, json), isEmpty, reason: c);
    }
  });

  group('records in and out', () {
    test('incoming timestamps become strings, JSON text is decoded', () {
      final data = fromRemote('tasks', {
        'createdAt': DateTime.utc(2026, 1, 2),
        'tags': '["a","b"]',
        'title': '["not decoded: titles are text"]',
        'subtasks': 'not json',
      });
      expect(data['createdAt'], '2026-01-02T00:00:00.000Z');
      expect(data['tags'], ['a', 'b']);
      expect(data['title'], '["not decoded: titles are text"]');
      expect(data['subtasks'], 'not json');
    });

    test('values the app can’t read are found and dropped', () {
      final data = {
        'title': 42,
        'tags': ['a', 1],
        'order': 'first',
        'assigneeId': null,
        'extra': 'kept',
      };
      expect(invalidFields('tasks', data).keys, ['title', 'order', 'tags']);
      expect(withoutInvalidFields('tasks', data), {
        'assigneeId': null,
        'extra': 'kept',
      });
    });

    test('lists and objects go to SQL as JSON text', () {
      expect(
        toSql({
          'tags': ['a'],
          'theme': {'accent': 1},
          'order': 2,
        }),
        {'tags': '["a"]', 'theme': '{"accent":1}', 'order': 2},
      );
    });
  });

  group('field fit', () {
    FieldSchema f(FieldKind kind) => FieldSchema(kind);
    test('per kind', () {
      expect(fits(ValueKind.string, f(FieldKind.string), false), isTrue);
      expect(fits(ValueKind.string, f(FieldKind.timestamp), false), isFalse);
      expect(fits(ValueKind.timestamp, f(FieldKind.timestamp), false), isTrue);
      expect(
        fits(ValueKind.stringList, f(FieldKind.stringList), false),
        isTrue,
      );
      expect(
        fits(ValueKind.objectList, f(FieldKind.stringList), false),
        isFalse,
      );
      expect(fits(ValueKind.object, f(FieldKind.json), false), isTrue);
      expect(fits(ValueKind.object, f(FieldKind.string), false), isFalse);
      expect(fits(ValueKind.object, f(FieldKind.string), true), isTrue);
      expect(fits(ValueKind.number, f(FieldKind.other), true), isFalse);
    });
  });

  group('checkCompatibility', () {
    test('a database that matches the app passes', () async {
      final db = FakeDatabase(schemas: matchingSchemas())
        ..put('tasks', 't', {'title': 'Ship', 'tags': '["a"]'});
      final report = await checkCompatibility(db);
      expect(report.compatible, isTrue, reason: '${report.results}');
      expect(
        report.results.where((r) => r.collection == 'tasks').single.message,
        contains('1 record checked'),
      );
    });

    test(
      'missing tables, missing fields, wrong types and bad data fail',
      () async {
        final schemas = matchingSchemas()..remove('activity');
        final tasks = schemas['tasks']!;
        schemas['tasks'] = CollectionSchema(
          fields: {
            ...tasks.fields..remove('placements'),
            'order': const FieldSchema(FieldKind.string, nativeType: 'text'),
            'assigneeId': const FieldSchema(
              FieldKind.string,
              nullable: false,
              nativeType: 'text',
            ),
            'secret': const FieldSchema(FieldKind.string, nullable: false),
          },
          notes: const [SchemaNote(SchemaNoteLevel.warning, 'Heads up.')],
        );
        final db = FakeDatabase(schemas: schemas)
          ..put('projects', 'p', {'name': 7});
        final report = await checkCompatibility(db);
        expect(report.compatible, isFalse);
        String messages(String c) => report.results
            .where((r) => r.collection == c)
            .map((r) => r.message)
            .join('\n');
        expect(messages('activity'), contains('no table named “activity”'));
        expect(messages('tasks'), contains('Missing the “placements” field'));
        expect(messages('tasks'), contains('“order” is text'));
        expect(messages('tasks'), contains('“assigneeId” can’t be left empty'));
        expect(messages('tasks'), contains('“secret” is required'));
        expect(messages('tasks'), contains('Heads up.'));
        expect(messages('projects'), contains('“name” should be text'));
      },
    );

    test(
      'read-only credentials fail; a schemaless database checks data only',
      () async {
        final readOnly = FakeDatabase(
          schemas: matchingSchemas(),
          writable: false,
        );
        expect(
          (await checkCompatibility(readOnly)).errors.first.message,
          contains('can’t write'),
        );
        final schemaless = MemoryAdapter()
          ..put('tasks', 't', {'title': 'Ship'});
        expect((await checkCompatibility(schemaless)).compatible, isTrue);
      },
    );

    test('a connection failure is the only finding', () async {
      final report = await checkCompatibility(_Unreachable());
      expect(report.results.single.message, startsWith('Couldn’t connect'));
    });
  });

  test('SyncService connects, syncs both ways, validates what comes in, '
      'and disconnects', () async {
    final store = LocalStore.inMemory();
    final remote = MemoryAdapter();
    final service = SyncService(
      store,
      collections: const ['tasks'],
      buildAdapter: (_, _) => remote,
    );
    const config = SanityConfig(projectId: 'p', dataset: 'd', token: 't');
    final report = await service.check(config);
    expect(report.compatible, isTrue);

    store.put('tasks', 'mine', {'title': 'From this Mac'});
    remote.put('tasks', 'theirs', {'title': 'From the database', 'order': 'x'});
    await service.connect(config, report);
    await service.current!.controller.syncNow();

    expect(remote.records('tasks')['mine']?['title'], 'From this Mac');
    expect(store.get('tasks', 'theirs'), {'title': 'From the database'});

    await service.disconnect();
    expect(service.current, isNull);
    expect(service.saved?.toJson(), config.toJson());
    service.start();
    expect(service.current, isNull, reason: 'disconnected stays so');
    await service.dispose();
    await store.close();
  });

  group('RemoteConfig', () {
    test('round-trips, names its database, and says what’s missing', () {
      const configs = <RemoteConfig>[
        SanityConfig(projectId: 'abc', dataset: 'production', token: 't'),
        ContentfulConfig(
          spaceId: 's',
          environment: 'master',
          deliveryToken: 'd',
          managementToken: 'm',
          locale: 'en-US',
        ),
        PostgresConfig(
          host: 'db.example.com',
          port: 5432,
          database: 'app',
          username: 'me',
          password: 'pw',
          ssl: false,
        ),
        MySqlConfig(
          host: 'localhost',
          port: 3306,
          database: 'app',
          username: 'root',
          password: '',
        ),
      ];
      for (final c in configs) {
        expect(RemoteConfig.fromJson(c.toJson())!.toJson(), c.toJson());
        expect(c.missing, isNull);
        expect(c.identity, isNot(contains('pw')));
      }
      expect(
        const SanityConfig(projectId: 'abc', dataset: ' ', token: 't').missing,
        'Dataset',
      );
      expect(RemoteConfig.fromJson({'kind': 'oracle'}), isNull);
      expect(configs[2].storesJsonAsText, isTrue);
    });
  });
}

class _Unreachable extends MemoryAdapter {
  @override
  Future<void> open() async => throw const SocketLikeException();
}

class SocketLikeException implements Exception {
  const SocketLikeException();
  @override
  String toString() => 'SocketException: Connection refused';
}
