import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_tools.dart';

/// MCP versions this server speaks, newest first. A client asking for one
/// of these gets it; any other gets the newest.
const mcpProtocolVersions = ['2025-11-25', '2025-06-18', '2025-03-26'];

/// The path the server answers on: `http://127.0.0.1:<port>/mcp`.
const mcpPath = '/mcp';

/// The app's MCP server (Model Context Protocol, "Streamable HTTP"): AI
/// assistants such as Claude connect to it and use [McpTools] to read and
/// change projects and tasks while the app is open.
///
/// Only reachable from this Mac (it listens on 127.0.0.1), and only with
/// the token (`Authorization: Bearer <token>`). Each request is one
/// JSON-RPC message, answered with one JSON response; no event streams.
final class McpServer {
  McpServer(this.tools, {required this.token});

  final McpTools tools;
  final String token;

  HttpServer? _http;

  /// The port it's listening on; null when stopped.
  int? get port => _http?.port;

  /// Starts listening on [port] (0 picks a free one). Throws a
  /// [SocketException] when the port is taken.
  Future<void> start(int port) async {
    await stop();
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _http = http;
    http.listen(_serve, onError: (_) {});
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    await http?.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != mcpPath) {
        return await _status(response, HttpStatus.notFound);
      }
      // A web page in a browser on this Mac can't reach it (DNS
      // rebinding): only local origins, or none (not a browser).
      final origin = request.headers.value('origin');
      if (origin != null && !_isLocal(origin)) {
        return await _status(response, HttpStatus.forbidden);
      }
      if (request.headers.value('authorization') != 'Bearer $token') {
        response.headers.set('WWW-Authenticate', 'Bearer');
        return await _status(response, HttpStatus.unauthorized);
      }
      switch (request.method) {
        case 'POST':
          break;
        case 'DELETE':
          // Ending a session: there are none to end.
          return await _status(response, HttpStatus.ok);
        default:
          // No event stream to open (GET) or anything else.
          response.headers.set('Allow', 'POST, DELETE');
          return await _status(response, HttpStatus.methodNotAllowed);
      }
      final Object? message;
      try {
        message = jsonDecode(await utf8.decoder.bind(request).join());
      } on FormatException {
        return await _json(response, _error(null, -32700, 'Parse error'));
      }
      final reply = await handle(message);
      if (reply == null) {
        // A notification or a client's response: nothing to say.
        return await _status(response, HttpStatus.accepted);
      }
      return await _json(response, reply);
    } catch (_) {
      // Already answered (or the client left): nothing more to do.
      try {
        await _status(response, HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  /// Answers one JSON-RPC [message] (or a batch of them); null when it
  /// needs no answer (notifications, responses).
  Future<Object?> handle(Object? message) async {
    if (message is List) {
      final replies = [for (final m in message) ?await handle(m)];
      return replies.isEmpty ? null : replies;
    }
    if (message is! Map<String, Object?>) {
      return _error(null, -32600, 'Invalid request');
    }
    final id = message['id'];
    final method = message['method'];
    // A response to something we never send, or a notification
    // (e.g. notifications/initialized): nothing to answer.
    if (method is! String || !message.containsKey('id')) return null;
    final params = switch (message['params']) {
      final Map<String, Object?> p => p,
      _ => const <String, Object?>{},
    };
    return switch (method) {
      'initialize' => _result(id, _initialize(params)),
      'ping' => _result(id, const {}),
      'tools/list' => _result(id, {
        'tools': [for (final t in tools.all) t.toJson()],
      }),
      'tools/call' => await _call(id, params),
      _ => _error(id, -32601, 'Method not found: $method'),
    };
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final asked = params['protocolVersion'];
    return {
      'protocolVersion': mcpProtocolVersions.contains(asked)
          ? asked
          : mcpProtocolVersions.first,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': 'codename', 'version': '1.0.0'},
      'instructions':
          'codename is a Kanban task app. Projects are boards with columns; '
          'tasks sit in a column and can be in several projects '
          '(multi-homed). Start with list_projects. Projects, columns and '
          'people can be named by id or name.',
    };
  }

  Future<Map<String, Object?>> _call(
    Object? id,
    Map<String, Object?> params,
  ) async {
    final name = params['name'];
    final tool = name is String ? tools.named(name) : null;
    if (tool == null) return _error(id, -32602, 'Unknown tool: $name');
    final args = switch (params['arguments']) {
      final Map<String, Object?> a => a,
      _ => const <String, Object?>{},
    };
    try {
      final result = await tool.run(args);
      return _result(id, {
        'content': [
          {
            'type': 'text',
            'text': const JsonEncoder.withIndent('  ').convert(result),
          },
        ],
        'structuredContent': {'result': result},
        'isError': false,
      });
    } on McpToolError catch (e) {
      return _result(id, {
        'content': [
          {'type': 'text', 'text': e.message},
        ],
        'isError': true,
      });
    }
  }

  static bool _isLocal(String origin) {
    final host = Uri.tryParse(origin)?.host;
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static Map<String, Object?> _result(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static Future<void> _status(HttpResponse response, int status) {
    response.statusCode = status;
    return response.close();
  }

  static Future<void> _json(HttpResponse response, Object? body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    return response.close();
  }
}
