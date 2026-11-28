import 'package:mysql1/mysql1.dart' as mysql;
import 'package:postgres/postgres.dart' as pg;
import 'package:sync_engine/sync_engine.dart';

import 'app_schema.dart';

/// The kinds of database the app can sync with: one per sync engine
/// adapter.
enum RemoteKind {
  sanity('Sanity'),
  contentful('Contentful'),
  postgres('PostgreSQL'),
  mysql('MySQL');

  const RemoteKind(this.label);
  final String label;
}

/// How to reach a database: what the user typed in Settings. Kept on this
/// Mac only (never synced), secrets included.
sealed class RemoteConfig {
  const RemoteConfig();

  RemoteKind get kind;

  /// Where it points, without secrets: "abc123 / production".
  String get description;

  /// Identifies the database (not the credentials). Sync progress is kept
  /// under it, so connecting to a different database starts afresh, and
  /// reconnecting to the same one carries on.
  String get identity;

  /// What's missing before it can be tried; null when complete.
  String? get missing;

  /// The adapter for it. [softDeletes] lists the SQL tables that have a
  /// `deleted_at` column, so deletes sync through them.
  SyncAdapter build({Set<String> softDeletes = const {}});

  /// Lists and objects go out as JSON text (SQL databases).
  bool get storesJsonAsText => false;

  Map<String, Object?> toJson();

  static RemoteConfig? fromJson(Map<String, Object?>? json) {
    String s(String key, [String fallback = '']) =>
        json?[key] as String? ?? fallback;
    int n(String key, int fallback) =>
        (json?[key] as num?)?.toInt() ?? fallback;
    return switch (json?['kind']) {
      'sanity' => SanityConfig(
        projectId: s('projectId'),
        dataset: s('dataset', 'production'),
        token: s('token'),
      ),
      'contentful' => ContentfulConfig(
        spaceId: s('spaceId'),
        environment: s('environment', 'master'),
        deliveryToken: s('deliveryToken'),
        managementToken: s('managementToken'),
        locale: s('locale', 'en-US'),
      ),
      'postgres' => PostgresConfig(
        host: s('host'),
        port: n('port', 5432),
        database: s('database'),
        username: s('username'),
        password: s('password'),
        ssl: json?['ssl'] != false,
      ),
      'mysql' => MySqlConfig(
        host: s('host'),
        port: n('port', 3306),
        database: s('database'),
        username: s('username'),
        password: s('password'),
      ),
      _ => null,
    };
  }
}

String? _firstMissing(Map<String, String> required) => required.entries
    .where((e) => e.value.trim().isEmpty)
    .map((e) => e.key)
    .firstOrNull;

final class SanityConfig extends RemoteConfig {
  const SanityConfig({
    required this.projectId,
    required this.dataset,
    required this.token,
  });

  final String projectId;
  final String dataset;

  /// Needs Editor (write) access.
  final String token;

  @override
  RemoteKind get kind => RemoteKind.sanity;

  @override
  String get description => '$projectId / $dataset';

  @override
  String get identity => 'sanity:$projectId/$dataset';

  @override
  String? get missing => _firstMissing({
    'Project ID': projectId,
    'Dataset': dataset,
    'API token': token,
  });

  @override
  SyncAdapter build({Set<String> softDeletes = const {}}) => SanityAdapter(
    projectId: projectId.trim(),
    dataset: dataset.trim(),
    token: token.trim(),
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'projectId': projectId,
    'dataset': dataset,
    'token': token,
  };
}

final class ContentfulConfig extends RemoteConfig {
  const ContentfulConfig({
    required this.spaceId,
    required this.environment,
    required this.deliveryToken,
    required this.managementToken,
    required this.locale,
  });

  final String spaceId;
  final String environment;

  /// Content Delivery API token, for reading.
  final String deliveryToken;

  /// Content Management API token, for writing.
  final String managementToken;
  final String locale;

  @override
  RemoteKind get kind => RemoteKind.contentful;

  @override
  String get description => '$spaceId / $environment';

  @override
  String get identity => 'contentful:$spaceId/$environment/$locale';

  @override
  String? get missing => _firstMissing({
    'Space ID': spaceId,
    'Environment': environment,
    'Delivery token': deliveryToken,
    'Management token': managementToken,
    'Locale': locale,
  });

  @override
  SyncAdapter build({Set<String> softDeletes = const {}}) => ContentfulAdapter(
    spaceId: spaceId.trim(),
    environment: environment.trim(),
    deliveryToken: deliveryToken.trim(),
    managementToken: managementToken.trim(),
    locale: locale.trim(),
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'spaceId': spaceId,
    'environment': environment,
    'deliveryToken': deliveryToken,
    'managementToken': managementToken,
    'locale': locale,
  };
}

/// Shared by the SQL databases.
sealed class SqlConfig extends RemoteConfig {
  const SqlConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  @override
  String get description => '$database on $host';

  @override
  String get identity => '${kind.name}:$host:$port/$database';

  @override
  String? get missing =>
      _firstMissing({'Host': host, 'Database': database, 'Username': username});

  @override
  bool get storesJsonAsText => true;

  /// The column settings for each synced table.
  Map<String, SqlTable> tables(Set<String> softDeletes) => {
    for (final c in appSchema.keys)
      c: SqlTable(
        deletedAtColumn: softDeletes.contains(c) ? 'deleted_at' : null,
      ),
  };
}

final class PostgresConfig extends SqlConfig {
  const PostgresConfig({
    required super.host,
    required super.port,
    required super.database,
    required super.username,
    required super.password,
    this.ssl = true,
  });

  /// Require an encrypted connection (most hosted databases do).
  final bool ssl;

  @override
  RemoteKind get kind => RemoteKind.postgres;

  /// Where the database is, as the driver wants it.
  pg.Endpoint get endpoint => pg.Endpoint(
    host: host.trim(),
    port: port,
    database: database.trim(),
    username: username.trim(),
    password: password,
  );

  pg.ConnectionSettings get connectionSettings => pg.ConnectionSettings(
    sslMode: ssl ? pg.SslMode.require : pg.SslMode.disable,
    connectTimeout: const Duration(seconds: 15),
    // A query on a connection that died silently (the network dropped
    // mid-sync) fails after this instead of hanging for the default 5
    // minutes, with the sync stuck at "Syncing…" meanwhile.
    queryTimeout: const Duration(seconds: 60),
  );

  /// A connection of its own (not the sync's), for one-off questions such
  /// as the Developer view's sizes. Close it when done.
  Future<pg.Connection> open() =>
      pg.Connection.open(endpoint, settings: connectionSettings);

  @override
  SyncAdapter build({Set<String> softDeletes = const {}}) => PostgresAdapter(
    endpoint: endpoint,
    settings: connectionSettings,
    tables: tables(softDeletes),
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'password': password,
    'ssl': ssl,
  };
}

final class MySqlConfig extends SqlConfig {
  const MySqlConfig({
    required super.host,
    required super.port,
    required super.database,
    required super.username,
    required super.password,
  });

  @override
  RemoteKind get kind => RemoteKind.mysql;

  @override
  SyncAdapter build({Set<String> softDeletes = const {}}) => MySqlAdapter(
    settings: mysql.ConnectionSettings(
      host: host.trim(),
      port: port,
      db: database.trim(),
      user: username.trim(),
      password: password.isEmpty ? null : password,
      timeout: const Duration(seconds: 15),
    ),
    tables: tables(softDeletes),
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'password': password,
  };
}
