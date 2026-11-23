import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import 'mcp_server.dart';
import 'mcp_tools.dart';

/// The port the MCP server listens on unless another is set.
const defaultMcpPort = 7429;

/// The MCP server's state, for Settings.
sealed class McpStatus {
  const McpStatus();
}

final class McpOff extends McpStatus {
  const McpOff();
}

final class McpRunning extends McpStatus {
  const McpRunning(this.port);
  final int port;
}

/// It's on, but couldn't start (the port is taken, say).
final class McpFailed extends McpStatus {
  const McpFailed(this.message);
  final String message;
}

/// Turns the app's MCP server on and off (Settings), and keeps it that
/// way across launches. The switch, port and token are kept on this Mac
/// only (`ui/mcp`, not synced): the server runs here.
final class McpService {
  McpService(this._store, this._tools);

  final LocalStore _store;
  final McpTools _tools;

  static const _collection = 'ui', _key = 'mcp';

  McpServer? _server;

  /// What it's doing now; Settings shows it.
  final status = ValueNotifier<McpStatus>(const McpOff());

  Map<String, Object?> get _saved => _store.get(_collection, _key) ?? const {};

  bool get enabled => _saved['enabled'] == true;

  int get port => switch (_saved['port']) {
    final int p when p > 0 && p < 65536 => p,
    _ => defaultMcpPort,
  };

  /// The secret a client sends (`Authorization: Bearer …`); made the first
  /// time it's needed.
  String get token => switch (_saved['token']) {
    final String t when t.isNotEmpty => t,
    _ => _write({'token': newId()})['token']! as String,
  };

  /// The address clients connect to.
  String get url => 'http://127.0.0.1:$port$mcpPath';

  /// Starts the server if it was left on. Call once, at launch.
  Future<void> restore() => enabled ? _start() : Future.value();

  Future<void> setEnabled(bool on) async {
    _write({'enabled': on});
    on ? await _start() : await _stop();
  }

  /// A new token: clients set up with the old one stop working.
  Future<void> regenerateToken() async {
    _write({'token': newId()});
    if (enabled) await _start();
  }

  Future<void> _start() async {
    final server = McpServer(_tools, token: token);
    await _stop();
    try {
      await server.start(port);
      _server = server;
      status.value = McpRunning(server.port!);
    } on SocketException catch (e) {
      status.value = McpFailed(
        // 48: EADDRINUSE on macOS.
        e.osError?.errorCode == 48
            ? 'Port $port is in use by another app.'
            : 'Couldn’t start: ${e.osError?.message ?? e.message}',
      );
    }
  }

  Future<void> _stop() async {
    final server = _server;
    _server = null;
    await server?.stop();
    status.value = const McpOff();
  }

  Map<String, Object?> _write(Map<String, Object?> changes) {
    final next = {..._saved, ...changes};
    _store.put(_collection, _key, next);
    return next;
  }

  Future<void> dispose() async {
    await _stop();
    status.dispose();
  }
}
