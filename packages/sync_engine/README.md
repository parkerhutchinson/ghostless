# sync_engine

A database-agnostic sync engine for Dart. Every backend implements one
interface, `SyncAdapter`, and `SyncEngine` moves changes between any two of
them — one-way or both ways — with checkpoints so runs resume where they
stopped.

Pure Dart (no Flutter dependency), so it runs in the app, a CLI or a server.

## Adapters

| Adapter | Collection = | Reads | Writes | Reports deletes |
| --- | --- | --- | --- | --- |
| `PostgresAdapter` | table | polling on `updated_at` | upsert, one transaction per batch | with a `deleted_at` column |
| `MySqlAdapter` | table | polling on `updated_at` | upsert, one transaction per batch | with a `deleted_at` column |
| `SanityAdapter` | document `_type` | GROQ query on `_updatedAt` (published) | `createOrReplace` / `delete` mutations | no |
| `ContentfulAdapter` | content type | Sync API (`sync_token`) | Management API, then publish | no |
| `MemoryAdapter` | any name | sequence number | in memory | yes |

To add a backend, implement `SyncAdapter`: `open`, `pull` (changes after an
opaque cursor, oldest first), `push` (idempotent upserts and deletes) and
`close`.

## Usage

```dart
final engine = SyncEngine(checkpoints: JsonFileCheckpointStore(File('.sync/checkpoints.json')))
  ..register('pg', PostgresAdapter(endpoint: Endpoint(host: 'localhost', database: 'app')))
  ..register('cms', SanityAdapter(projectId: 'abc123', dataset: 'production', token: token));

final report = await engine.run(SyncPipeline(
  id: 'posts-to-cms',
  source: 'pg',
  target: 'cms',
  collections: [
    CollectionMapping('posts', target: 'post', toTarget: (row) => {'title': row['title']}),
  ],
));
print(report);
```

Two-way sync: set `direction: SyncDirection.bidirectional`, add `toSource` to
mappings that reshape data, and optionally pick a `resolveConflict`
(`ConflictResolvers.lastWriteWins` is the default).

## Offline-first apps

`LocalStore` is an on-device SQLite database that is also a `SyncAdapter`.
The app only ever reads and writes the store; `SyncController` syncs it
two-way with a remote in the background.

```dart
final store = LocalStore.open('$appSupportDir/app.db');
final engine = SyncEngine(checkpoints: store.checkpoints)
  ..register('local', store)
  ..register('remote', SanityAdapter(...));
final sync = SyncController(
  engine: engine,
  store: store,
  pipeline: const SyncPipeline(
    id: 'app', source: 'local', target: 'remote',
    direction: SyncDirection.bidirectional,
    collections: [CollectionMapping('notes')],
  ),
)..start();

store.put('notes', id, {'text': 'hi'}); // on disk now, online or not
store.watch('notes');                   // UI stream; includes synced-in changes
sync.statusStream;                      // idle / syncing / offline + pending count
```

- Writes commit locally before any network call; nothing is lost offline.
- The controller syncs ~2s after a write, every minute, and on `syncNow()`;
  failures retry with exponential backoff (up to 5 minutes).
- Records and checkpoints share one database, so they stay consistent
  across crashes.
- An incoming remote change never overwrites a newer local write.

## How it works

- **Records** are `Change`s: an id, a field map, an updated-at time, and
  upsert or delete. Ids must be the same across the systems in a pipeline.
- **One-way** pipelines stream page by page and save the source cursor after
  each successful push, so a failure retries from the last good page.
- **Two-way** pipelines read everything pending on both sides, resolve
  records changed on both, then push each way. The engine stores a
  fingerprint of every record it writes, so when a write comes back in the
  other side's next pull it is skipped instead of echoed.
- **Checkpoints** (cursors and fingerprints) go to a `CheckpointStore`:
  in memory, a JSON file, or your own implementation.

## SQL table requirements

Each synced table needs an id column and an updated-at timestamp that
changes on every write (a trigger or ORM hook usually maintains it), with
sub-second precision (`timestamptz` / `DATETIME(6)`). Column names are
configurable with `SqlTable`. Hard `DELETE`s can't be seen by polling; give
the table a `deleted_at` column to sync deletes.

## Known limitations

- Polling SQL by timestamp can miss a row whose transaction commits after a
  later row was already read. Change data capture (logical replication,
  binlog) would close that gap.
- Sanity and Contentful don't report deletes yet (needs Sanity's history API
  or webhooks, and Contentful deletion sync).
- Two-way sync holds a run's pending changes in memory.
- The Postgres and MySQL adapters are covered by SQL-generation tests only;
  they haven't run against live databases yet.

## Tests

```sh
dart test
```
