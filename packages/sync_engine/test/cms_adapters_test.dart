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

void main() {
  group('Sanity', () {
    test('pull queries by type and strips system fields', () async {
      late Uri seen;
      final sanity = SanityAdapter(
        projectId: 'proj',
        dataset: 'production',
        client: MockClient((req) async {
          seen = req.url;
          return json({
            'result': [
              {
                '_id': 'post-1',
                '_type': 'post',
                '_rev': 'r1',
                '_createdAt': '2026-01-01T00:00:00Z',
                '_updatedAt': '2026-01-02T00:00:00Z',
                'title': 'Hello',
              },
            ],
          });
        }),
      );

      final page = await sanity.pull('post', limit: 1);
      expect(seen.host, 'proj.api.sanity.io');
      expect(seen.path, '/v2025-02-19/data/query/production');
      expect(seen.queryParameters[r'$type'], '"post"');
      expect(seen.queryParameters['query'], contains('[0...1]'));
      expect(page.changes.single.data, {'title': 'Hello'});
      expect(page.cursor, '2026-01-02T00:00:00Z|post-1');
      expect(page.hasMore, isTrue);
    });

    test('push sends createOrReplace and delete mutations', () async {
      late Map<String, dynamic> body;
      late http.Request request;
      final sanity = SanityAdapter(
        projectId: 'proj',
        dataset: 'production',
        token: 'secret',
        client: MockClient((req) async {
          request = req;
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return json({'transactionId': 'tx'});
        }),
      );

      await sanity.push('post', [
        Change.upsert(id: 'a', data: {'title': 'A'}, updatedAt: DateTime.now()),
        Change.delete(id: 'b', updatedAt: DateTime.now()),
      ]);
      expect(request.headers['Authorization'], 'Bearer secret');
      expect(body['mutations'], [
        {
          'createOrReplace': {'title': 'A', '_id': 'a', '_type': 'post'},
        },
        {
          'delete': {'id': 'b'},
        },
      ]);
    });

    test('errors become SyncAdapterException', () async {
      final sanity = SanityAdapter(
        projectId: 'p',
        dataset: 'd',
        client: MockClient((_) async => json({'error': 'nope'}, 401)),
      );
      expect(sanity.pull('post'), throwsA(isA<SyncAdapterException>()));
    });

    test('without a token it is read-only', () {
      expect(
        SanityAdapter(projectId: 'p', dataset: 'd').capabilities.canWrite,
        isFalse,
      );
    });
  });

  group('Contentful', () {
    test(
      'initial sync filters by content type and flattens the locale',
      () async {
        late Uri seen;
        final contentful = ContentfulAdapter(
          spaceId: 'space',
          deliveryToken: 'cda',
          client: MockClient((req) async {
            seen = req.url;
            return json({
              'items': [
                {
                  'sys': {
                    'id': 'e1',
                    'type': 'Entry',
                    'updatedAt': '2026-01-02T00:00:00Z',
                    'contentType': {
                      'sys': {'id': 'blogPost'},
                    },
                  },
                  'fields': {
                    'title': {'en-US': 'Hello', 'de-DE': 'Hallo'},
                  },
                },
              ],
              'nextSyncUrl': 'https://cdn.contentful.com/spaces/space/environments/master/sync?sync_token=tok123',
            });
          }),
        );

        final page = await contentful.pull('blogPost');
        expect(seen.path, '/spaces/space/environments/master/sync');
        expect(seen.queryParameters, containsPair('content_type', 'blogPost'));
        expect(seen.queryParameters, containsPair('initial', 'true'));
        expect(page.changes.single.data, {'title': 'Hello'});
        expect(page.cursor, 'tok123');
        expect(page.hasMore, isFalse);

        await contentful.pull('blogPost', cursor: 'tok123');
        expect(seen.queryParameters, {'sync_token': 'tok123'});
      },
    );

    test('push creates a new entry, keeping other locales on update, then publishes', () async {
      final calls = <String>[];
      final entries = <String, Map<String, dynamic>>{
        'e2': {
          'sys': {'version': 3},
          'fields': {
            'title': {'en-US': 'Old', 'de-DE': 'Alt'},
          },
        },
      };
      final contentful = ContentfulAdapter(
        spaceId: 'space',
        managementToken: 'cma',
        client: MockClient((req) async {
          final id = req.url.pathSegments[5];
          final published = req.url.path.endsWith('/published');
          calls.add(
            '${req.method} $id${published ? '/published' : ''} '
            'v=${req.headers['X-Contentful-Version']} '
            'ct=${req.headers['X-Contentful-Content-Type']}',
          );
          if (req.method == 'GET') {
            return entries[id] == null ? json({}, 404) : json(entries[id]!);
          }
          if (req.method == 'PUT' && !published) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            entries[id] = {
              'sys': {
                'version': (entries[id]?['sys']['version'] as int? ?? 0) + 1,
              },
              ...body,
            };
            return json(entries[id]!);
          }
          return json({
            'sys': {'version': 99},
          });
        }),
      );

      await contentful.push('blogPost', [
        Change.upsert(
          id: 'e1',
          data: {'title': 'New'},
          updatedAt: DateTime.now(),
        ),
        Change.upsert(
          id: 'e2',
          data: {'title': 'Updated'},
          updatedAt: DateTime.now(),
        ),
      ]);

      expect(calls, [
        'GET e1 v=null ct=null',
        'PUT e1 v=null ct=blogPost',
        'PUT e1/published v=1 ct=null',
        'GET e2 v=null ct=null',
        'PUT e2 v=3 ct=null',
        'PUT e2/published v=4 ct=null',
      ]);
      expect(entries['e2']!['fields'], {
        'title': {'en-US': 'Updated', 'de-DE': 'Alt'},
      });
    });

    test('delete unpublishes first and ignores missing entries', () async {
      final calls = <String>[];
      final contentful = ContentfulAdapter(
        spaceId: 'space',
        managementToken: 'cma',
        client: MockClient((req) async {
          calls.add('${req.method} ${req.url.pathSegments.skip(5).join('/')}');
          if (req.method == 'GET') {
            return req.url.path.endsWith('/gone')
                ? json({}, 404)
                : json({
                    'sys': {'version': 5, 'publishedVersion': 4},
                  });
          }
          return json({
            'sys': {'version': 6},
          });
        }),
      );

      await contentful.push('blogPost', [
        Change.delete(id: 'live', updatedAt: DateTime.now()),
        Change.delete(id: 'gone', updatedAt: DateTime.now()),
      ]);
      expect(calls, [
        'GET live',
        'DELETE live/published',
        'DELETE live',
        'GET gone',
      ]);
    });
  });
}
