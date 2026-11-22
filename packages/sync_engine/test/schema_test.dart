import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> column(
  String name,
  String type, {
  bool nullable = true,
  Object? defaultValue,
}) => {
  'column_name': name,
  'data_type': type,
  'is_nullable': nullable ? 'YES' : 'NO',
  'column_default': defaultValue,
};

void main() {
  group('SQL schema', () {
    const pg = PostgresDialect();
    const my = MySqlDialect();

    test('describe statements look the table up by schema and name', () {
      expect(pg.describe('tasks').params, [null, 'tasks']);
      expect(pg.describe('app.tasks').params, ['app', 'tasks']);
      expect(my.describe('tasks').sql, contains('DATABASE()'));
      expect(my.describe('app.tasks').params, ['app', 'tasks']);
      expect(pg.writePrivileges('app.tasks').params, ['"app"."tasks"']);
    });

    test('column types map to field kinds', () {
      expect(pg.kindOf('jsonb'), FieldKind.json);
      expect(pg.kindOf('character varying'), FieldKind.string);
      expect(pg.kindOf('timestamp with time zone'), FieldKind.timestamp);
      expect(pg.kindOf('ARRAY'.toLowerCase()), FieldKind.other);
      expect(my.kindOf('longtext'), FieldKind.string);
      expect(my.kindOf('double'), FieldKind.number);
      expect(my.kindOf('json'), FieldKind.json);
    });

    test('builds fields without system columns, and checks them', () {
      final schema = pg.schemaFrom([
        column('id', 'text', nullable: false),
        column('updated_at', 'timestamp with time zone', nullable: false),
        column('title', 'text', nullable: false, defaultValue: "''"),
        column('tags', 'jsonb'),
      ], const SqlTable())!;
      expect(schema.fields.keys, ['title', 'tags']);
      expect(schema.fields['title']!.required, isFalse);
      expect(schema.fields['tags']!.kind, FieldKind.json);
      expect(schema.notes, isEmpty);
      expect(schema.jsonInText, isTrue);
    });

    test('notes missing or wrong system columns; no rows is no table', () {
      final schema = pg.schemaFrom([
        column('updated_at', 'text'),
      ], const SqlTable(deletedAtColumn: 'deleted_at'))!;
      expect(schema.notes.map((n) => n.message), [
        contains('"id"'),
        contains('needs to be a timestamp'),
        contains('"deleted_at"'),
      ]);
      expect(pg.schemaFrom(const [], const SqlTable()), isNull);
      // MySQL reports upper-case keys unless aliased.
      final upper = my.schemaFrom([
        {
          'COLUMN_NAME': 'id',
          'DATA_TYPE': 'varchar',
          'IS_NULLABLE': 'NO',
          'COLUMN_DEFAULT': null,
        },
      ], const SqlTable())!;
      expect(upper.notes.single.message, contains('updated_at'));
    });
  });

  group('Sanity', () {
    test('has no schema; checks writes with a dry run', () async {
      late http.Request seen;
      final sanity = SanityAdapter(
        projectId: 'proj',
        dataset: 'production',
        token: 'secret',
        client: MockClient((req) async {
          seen = req;
          return json({'transactionId': 'tx'});
        }),
      );
      expect(sanity.hasSchema, isFalse);
      expect(await sanity.describe('tasks'), isNull);
      expect(await sanity.canWrite('tasks'), isTrue);
      expect(seen.url.queryParameters['dryRun'], 'true');
      final mutation = (jsonDecode(seen.body)['mutations'] as List).single;
      expect(mutation['createOrReplace']['_type'], 'tasks');
    });

    test('a read-only token, or none, cannot write', () async {
      final readOnly = SanityAdapter(
        projectId: 'proj',
        dataset: 'production',
        token: 'viewer',
        client: MockClient((_) async => json({'error': 'nope'}, 403)),
      );
      expect(await readOnly.canWrite('tasks'), isFalse);
      final anonymous = SanityAdapter(projectId: 'proj', dataset: 'production');
      expect(await anonymous.canWrite('tasks'), isFalse);
    });
  });

  group('Contentful', () {
    MockClient client({bool missing = false, String locale = 'en-US'}) =>
        MockClient((req) async {
          if (req.url.path.endsWith('/locales')) {
            return json({
              'items': [
                {'code': locale},
              ],
            });
          }
          if (missing) return json({'sys': {}}, 404);
          return json({
            'fields': [
              {'id': 'title', 'type': 'Symbol', 'required': true},
              {
                'id': 'tags',
                'type': 'Array',
                'items': {'type': 'Symbol'},
              },
              {'id': 'subtasks', 'type': 'Object'},
              {'id': 'order', 'type': 'Number'},
              {
                'id': 'photo',
                'type': 'Link',
                'linkType': 'Asset',
                'omitted': true,
              },
            ],
          });
        });

    test('describes a content type from the management API', () async {
      final adapter = ContentfulAdapter(
        spaceId: 's',
        managementToken: 'm',
        client: client(),
      );
      final schema = (await adapter.describe('tasks'))!;
      expect(schema.fields.keys, ['title', 'tags', 'subtasks', 'order']);
      expect(schema.fields['title']!.required, isTrue);
      expect(schema.fields['tags']!.kind, FieldKind.stringList);
      expect(schema.fields['subtasks']!.kind, FieldKind.json);
      expect(schema.notes, isEmpty);
      expect(await adapter.canWrite('tasks'), isTrue);
    });

    test(
      'a missing content type, a missing locale, no management token',
      () async {
        final missing = ContentfulAdapter(
          spaceId: 's',
          deliveryToken: 'd',
          client: client(missing: true),
        );
        expect(await missing.describe('tasks'), isNull);
        expect(await missing.canWrite('tasks'), isFalse);
        final wrongLocale = ContentfulAdapter(
          spaceId: 's',
          deliveryToken: 'd',
          client: client(locale: 'de-DE'),
        );
        expect(
          (await wrongLocale.describe('tasks'))!.notes.single.message,
          contains('"en-US"'),
        );
      },
    );
  });
}
