import 'package:http/http.dart' as http;

import '../core/adapter.dart';
import '../core/change.dart';
import '../core/json.dart';
import '../core/schema.dart';
import 'http_util.dart';

/// Syncs Contentful entries. Collection names are content type ids.
///
/// Reads through the Content Delivery **Sync API**, whose `sync_token` is the
/// cursor, so only published entries are seen. Writes go through the Content
/// Management API, one entry at a time, publishing each by default.
///
/// Records are flattened to one [locale]: `{"title": {"en-US": "Hi"}}` in
/// Contentful is `{"title": "Hi"}` in the record. Pushing merges into the
/// existing entry, so other locales are kept.
///
/// Limitations:
/// - Deletes made in Contentful are not reported: the Sync API can only
///   filter by content type for entries, not deletions.
/// - Pushes aren't atomic across a batch (the CMA has no transactions);
///   a failure part-way leaves earlier entries written. Re-sending is safe.
class ContentfulAdapter implements SyncAdapter, SchemaInspector {
  ContentfulAdapter({
    required this.spaceId,
    this.environment = 'master',
    this.deliveryToken,
    this.managementToken,
    this.locale = 'en-US',
    this.publish = true,
    http.Client? client,
    Uri? deliveryBase,
    Uri? managementBase,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _cda = deliveryBase ?? Uri.https('cdn.contentful.com'),
       _cma = managementBase ?? Uri.https('api.contentful.com');

  final String spaceId;
  final String environment;

  /// Content Delivery API token, for reads.
  final String? deliveryToken;

  /// Content Management API token, for writes.
  final String? managementToken;

  final String locale;

  /// Publish entries after writing them (needed for them to sync back out).
  final bool publish;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _cda;
  final Uri _cma;

  static const _cmaJson = 'application/vnd.contentful.management.v1+json';

  @override
  String get name => 'contentful:$spaceId/$environment';

  @override
  AdapterCapabilities get capabilities => AdapterCapabilities(
    canRead: deliveryToken != null,
    canWrite: managementToken != null,
    reportsDeletes: false,
  );

  String get _envPath => '/spaces/$spaceId/environments/$environment';

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }

  // ------------------------------------------------------------------ reads

  @override
  Future<ChangePage> pull(
    String collection, {
    String? cursor,
    int limit = 500,
  }) async {
    final uri = _cda.replace(
      path: '$_envPath/sync',
      queryParameters: cursor == null
          ? {
              'initial': 'true',
              'type': 'Entry',
              'content_type': collection,
              'limit': '${limit.clamp(1, 1000)}',
            }
          : {'sync_token': cursor},
    );
    final body = decodeOrThrow(
      name,
      await sendWithRetry(
        _client,
        () =>
            http.Request('GET', uri)
              ..headers['Authorization'] = 'Bearer $deliveryToken',
      ),
    );
    final changes = <Change>[];
    for (final item in (body['items'] as List).cast<Map<String, dynamic>>()) {
      final sys = item['sys'] as Map<String, dynamic>;
      final updatedAt = DateTime.parse(
        (sys['updatedAt'] ?? sys['deletedAt']) as String,
      );
      final contentType = (sys['contentType'] as Map?)?['sys']?['id'];
      switch (sys['type']) {
        case 'Entry' when contentType == collection:
          changes.add(
            Change.upsert(
              id: sys['id'] as String,
              updatedAt: updatedAt,
              data: _flatten(item['fields'] as Map<String, dynamic>? ?? {}),
            ),
          );
        case 'DeletedEntry':
          changes.add(
            Change.delete(id: sys['id'] as String, updatedAt: updatedAt),
          );
      }
    }
    final next = (body['nextPageUrl'] ?? body['nextSyncUrl']) as String?;
    return ChangePage(
      changes: changes,
      cursor: next == null
          ? null
          : Uri.parse(next).queryParameters['sync_token'],
      hasMore: body['nextPageUrl'] != null,
    );
  }

  Map<String, Object?> _flatten(Map<String, dynamic> fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      if (value is Map && value.containsKey(locale)) key: value[locale],
  };

  // ----------------------------------------------------------------- schema

  @override
  bool get hasSchema => true;

  /// The content type's fields, read with the management token when there
  /// is one (it sees unpublished content types too), else the delivery
  /// token. Also checks that [locale] exists.
  @override
  Future<CollectionSchema?> describe(String collection) async {
    final response = await _read('$_envPath/content_types/$collection');
    if (response.statusCode == 404) return null;
    final body = decodeOrThrow(name, response);
    final locales = decodeOrThrow(name, await _read('$_envPath/locales'));
    final codes = [
      for (final l in (locales['items'] as List? ?? const []))
        (l as Map)['code'],
    ];
    return CollectionSchema(
      fields: {
        for (final f in (body['fields'] as List? ?? const []).cast<Map>())
          if (f['omitted'] != true && f['disabled'] != true)
            f['id'] as String: FieldSchema(
              _kindOf(f),
              nullable: f['required'] != true,
              nativeType: f['type'] == 'Array'
                  ? 'Array of ${(f['items'] as Map?)?['type']}'
                  : '${f['type']}',
            ),
      },
      notes: [
        if (!codes.contains(locale))
          SchemaNote(
            SchemaNoteLevel.error,
            'The environment has no "$locale" locale.',
          ),
      ],
    );
  }

  static FieldKind _kindOf(Map field) => switch (field['type']) {
    'Symbol' || 'Text' => FieldKind.string,
    'Integer' || 'Number' => FieldKind.number,
    'Boolean' => FieldKind.boolean,
    'Date' => FieldKind.timestamp,
    'Object' => FieldKind.json,
    'Array' when (field['items'] as Map?)?['type'] == 'Symbol' =>
      FieldKind.stringList,
    _ => FieldKind.other,
  };

  /// Writes need a management token that can see the content type.
  @override
  Future<bool?> canWrite(String collection) async {
    if (managementToken == null) return false;
    final response = await _send('GET', '$_envPath/content_types/$collection');
    return response.statusCode < 400;
  }

  Future<http.Response> _read(String path) => managementToken != null
      ? _send('GET', path)
      : sendWithRetry(
          _client,
          () =>
              http.Request('GET', _cda.replace(path: path))
                ..headers['Authorization'] = 'Bearer $deliveryToken',
        );

  // ----------------------------------------------------------------- writes

  @override
  Future<void> push(String collection, List<Change> changes) async {
    for (final c in changes) {
      await (c.isDelete ? _delete(c.id) : _upsert(collection, c));
    }
  }

  Future<void> _upsert(String contentType, Change c) async {
    final existing = await _getEntry(c.id);
    final fields = <String, dynamic>{
      ...?existing?['fields'] as Map<String, dynamic>?,
    };
    c.data!.forEach((key, value) {
      fields[key] = {...?fields[key] as Map<String, dynamic>?, locale: value};
    });
    final saved = await _cmaRequest(
      'PUT',
      '$_envPath/entries/${c.id}',
      version: existing?['sys']['version'] as int?,
      contentType: existing == null ? contentType : null,
      body: {'fields': fields},
    );
    if (publish) {
      await _cmaRequest(
        'PUT',
        '$_envPath/entries/${c.id}/published',
        version: saved['sys']['version'] as int,
      );
    }
  }

  Future<void> _delete(String id) async {
    var entry = await _getEntry(id);
    if (entry == null) return; // already gone
    if (entry['sys']['publishedVersion'] != null) {
      entry = await _cmaRequest(
        'DELETE',
        '$_envPath/entries/$id/published',
        version: entry['sys']['version'] as int,
      );
    }
    await _cmaRequest(
      'DELETE',
      '$_envPath/entries/$id',
      version: entry['sys']['version'] as int,
    );
  }

  Future<Map<String, dynamic>?> _getEntry(String id) async {
    final response = await _send('GET', '$_envPath/entries/$id');
    if (response.statusCode == 404) return null;
    return decodeOrThrow(name, response);
  }

  Future<Map<String, dynamic>> _cmaRequest(
    String method,
    String path, {
    int? version,
    String? contentType,
    Map<String, dynamic>? body,
  }) async => decodeOrThrow(
    name,
    await _send(
      method,
      path,
      version: version,
      contentType: contentType,
      body: body,
    ),
  );

  Future<http.Response> _send(
    String method,
    String path, {
    int? version,
    String? contentType,
    Map<String, dynamic>? body,
  }) => sendWithRetry(_client, () {
    final request = http.Request(method, _cma.replace(path: path))
      ..headers.addAll({
        'Authorization': 'Bearer $managementToken',
        'Content-Type': _cmaJson,
        'X-Contentful-Version': ?version?.toString(),
        'X-Contentful-Content-Type': ?contentType,
      });
    if (body != null) request.body = encodeJson(body);
    return request;
  });
}
