import 'dart:io';

import 'package:postgres/postgres.dart' show Endpoint;
import 'package:sync_engine/sync_engine.dart';

/// Publishes Postgres `posts` rows to Sanity `post` documents.
///
/// Credentials come from the environment; nothing here is real.
Future<void> main() async {
  final env = Platform.environment;
  final engine =
      SyncEngine(
          checkpoints: JsonFileCheckpointStore(File('.sync/checkpoints.json')),
        )
        ..register(
          'pg',
          PostgresAdapter(
            endpoint: Endpoint(
              host: env['PG_HOST'] ?? 'localhost',
              database: env['PG_DB'] ?? 'app',
              username: env['PG_USER'],
              password: env['PG_PASSWORD'],
            ),
            tables: {'posts': const SqlTable(deletedAtColumn: 'deleted_at')},
          ),
        )
        ..register(
          'sanity',
          SanityAdapter(
            projectId: env['SANITY_PROJECT']!,
            dataset: 'production',
            token: env['SANITY_TOKEN'],
          ),
        );

  final report = await engine.run(
    SyncPipeline(
      id: 'posts-to-sanity',
      source: 'pg',
      target: 'sanity',
      collections: [
        CollectionMapping(
          'posts',
          target: 'post',
          toTarget: (row) => {'title': row['title'], 'body': row['body']},
        ),
      ],
    ),
  );
  print(report);
  await engine.close();
}
