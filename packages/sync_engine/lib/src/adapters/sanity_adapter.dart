import 'package:http/http.dart' as http;

import '../core/adapter.dart';
import '../core/change.dart';
import '../core/json.dart';
import '../core/schema.dart';
import 'http_util.dart';

/// Syncs Sanity documents. Collection names are document `_type`s.
///
/// Reads published documents through the HTTP query API, ordered by
/// `_updatedAt` then `_id`. Writes use `createOrReplace` and `delete`
/// mutations, one transaction per batch.
///
/// Limitations:
/// - Deletes made in Sanity are not reported (a query can't see deleted
///   documents). Adding them needs Sanity's history API or a webhook.
/// - Sanity sets `_updatedAt` itself, so a pushed record's timestamp becomes
///   the time of the write, not the source's.
class SanityAdapter implements SyncAdapter, SchemaInspector {
  SanityAdapter({
    required this.projectId,
    required this.dataset,
    this.token,
    this.apiVersion = 'v2025-02-19',
    http.Client? client,
    Uri? baseUri,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _base = baseUri ?? Uri.https('$projectId.api.sanity.io');

  final String projectId;
  final String dataset;

  /// API token. Required for writes and for private datasets.
  final String? token;

  /// Sanity API version (a date), e.g. `v2025-02-19`.
  final String apiVersion;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _base;

  /// System fields kept out of record data (they map to id/updatedAt).
  static const _systemFields = {
    '_id',
    '_type',
    '_rev',
    '_createdAt',
    '_updatedAt',
  };
  static const _batchSize = 200;

  @override
  String get name => 'sanity:$projectId/$dataset';

  @override
  AdapterCapabilities get capabilities =>
      AdapterCapabilities(canWrite: token != null, reportsDeletes: false);

  Map<String, String> get _headers => {
    if (token != null) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }

  @override
  Future<ChangePage> pull(
    String collection, {
    String? cursor,
    int limit = 500,
  }) async {
    final (since, afterId) = _decodeCursor(cursor);
    final uri = _base.replace(
      path: '/$apiVersion/data/query/$dataset',
      queryParameters: {
        'query':
            r'*[_type == $type && (_updatedAt > $since || '
            r'(_updatedAt == $since && _id > $afterId))]'
            ' | order(_updatedAt asc, _id asc) [0...$limit]',
        r'$type': encodeJson(collection),
        r'$since': encodeJson(since),
        r'$afterId': encodeJson(afterId),
        'perspective': 'published',
      },
    );
    final body = decodeOrThrow(
      name,
      await sendWithRetry(
        _client,
        () => http.Request('GET', uri)..headers.addAll(_headers),
      ),
    );
    final docs = (body['result'] as List).cast<Map<String, dynamic>>();
    final changes = [
      for (final doc in docs)
        Change.upsert(
          id: doc['_id'] as String,
          updatedAt: DateTime.parse(doc['_updatedAt'] as String),
          data: {
            for (final MapEntry(:key, :value) in doc.entries)
              if (!_systemFields.contains(key)) key: value,
          },
        ),
    ];
    return ChangePage(
      changes: changes,
      cursor: docs.isEmpty
          ? null
          : '${docs.last['_updatedAt']}|${docs.last['_id']}',
      hasMore: docs.length == limit,
    );
  }

  @override
  Future<void> push(String collection, List<Change> changes) async {
    for (var i = 0; i < changes.length; i += _batchSize) {
      final batch = changes.skip(i).take(_batchSize);
      final mutations = [
        for (final c in batch)
          c.isDelete
              ? {
                  'delete': {'id': c.id},
                }
              : {
                  'createOrReplace': {
                    ...c.data!,
                    '_id': c.id,
                    '_type': collection,
                  },
                },
      ];
      final uri = _base.replace(
        path: '/$apiVersion/data/mutate/$dataset',
        queryParameters: {'returnIds': 'false', 'visibility': 'sync'},
      );
      decodeOrThrow(
        name,
        await sendWithRetry(
          _client,
          () => http.Request('POST', uri)
            ..headers.addAll(_headers)
            ..body = encodeJson({'mutations': mutations}),
        ),
      );
    }
  }

  /// Sanity datasets have no schema the API can report.
  @override
  bool get hasSchema => false;

  @override
  Future<CollectionSchema?> describe(String collection) async => null;

  /// Sends a dry-run mutation (nothing is written): Sanity checks the
  /// token's permissions without applying it.
  @override
  Future<bool?> canWrite(String collection) async {
    if (token == null) return false;
    final uri = _base.replace(
      path: '/$apiVersion/data/mutate/$dataset',
      queryParameters: {'dryRun': 'true', 'returnIds': 'false'},
    );
    final response = await sendWithRetry(
      _client,
      () => http.Request('POST', uri)
        ..headers.addAll(_headers)
        ..body = encodeJson({
          'mutations': [
            {
              'createOrReplace': {
                '_id': 'sync-engine-write-check',
                '_type': collection,
              },
            },
          ],
        }),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      return false;
    }
    decodeOrThrow(name, response);
    return true;
  }

  static (String, String) _decodeCursor(String? cursor) {
    if (cursor == null) return ('1970-01-01T00:00:00Z', '');
    final split = cursor.indexOf('|');
    return (cursor.substring(0, split), cursor.substring(split + 1));
  }
}
