import 'package:http/http.dart' as http;

import '../core/adapter.dart';
import '../core/change.dart';
import '../core/json.dart';
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
class ContentfulAdapter implements SyncAdapter {
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
