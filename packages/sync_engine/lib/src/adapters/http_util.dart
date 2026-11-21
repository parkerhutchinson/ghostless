import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/adapter.dart';

/// Sends a request built by [build], retrying rate limits (429) and server
/// errors (5xx) with backoff. Honors `Retry-After` and Contentful's
/// `X-Contentful-RateLimit-Reset` headers.
Future<http.Response> sendWithRetry(
  http.Client client,
  http.BaseRequest Function() build, {
  int maxAttempts = 5,
}) async {
  for (var attempt = 1; ; attempt++) {
    final response = await http.Response.fromStream(await client.send(build()));
    final retryable = response.statusCode == 429 || response.statusCode >= 500;
    if (!retryable || attempt >= maxAttempts) return response;
    final header =
        response.headers['retry-after'] ??
        response.headers['x-contentful-ratelimit-reset'];
    final seconds = header == null ? null : int.tryParse(header);
    await Future<void>.delayed(
      seconds != null
          ? Duration(seconds: seconds)
          : Duration(milliseconds: 250 * pow(2, attempt).toInt()),
    );
  }
}

/// Decodes a JSON object body, or throws [SyncAdapterException] on an error
/// status.
Map<String, dynamic> decodeOrThrow(String adapter, http.Response response) {
  if (response.statusCode >= 400) {
    throw SyncAdapterException(
      adapter,
      'HTTP ${response.statusCode} from ${response.request?.method} '
      '${response.request?.url.path}: ${response.body}',
    );
  }
  if (response.body.isEmpty) return const {};
  return jsonDecode(response.body) as Map<String, dynamic>;
}
