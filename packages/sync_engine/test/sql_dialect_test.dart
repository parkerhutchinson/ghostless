import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 3, 4, 5, 6, 7, 8, 9);
  final upsert = Change.upsert(
    id: '7',
    updatedAt: at,
    data: {
      'title': 'Hi',
      'tags': ['a'],
      'id': 'ignored',
    },
  );
  final delete = Change.delete(id: '7', updatedAt: at);
  const soft = SqlTable(deletedAtColumn: 'deleted_at');

  group('Postgres', () {
    const pg = PostgresDialect();

    test('first pull has no cursor filter', () {
      final s = pg.pull('public.posts', const SqlTable(), null, 100);
      expect(
        s.sql,
        'SELECT * FROM "public"."posts" ORDER BY "updated_at", "id" LIMIT 100',
      );
      expect(s.params, isEmpty);
    });

    test('later pulls continue after the cursor', () {
      final cursor = SqlDialect.encodeCursor(upsert);
      final s = pg.pull('posts', const SqlTable(), cursor, 10);
      expect(s.sql, contains(r'WHERE ("updated_at", "id") > ($1, $2)'));
      expect(s.params, [at, '7']);
    });

    test('upsert skips system columns from data and resets soft delete', () {
      final s = pg.upsert('posts', soft, upsert);
      expect(
        s.sql,
        'INSERT INTO "posts" ("id", "updated_at", "deleted_at", "title", "tags") '
        r'VALUES ($1, $2, $3, $4, $5) '
        'ON CONFLICT ("id") DO UPDATE SET "updated_at" = EXCLUDED."updated_at", '
        '"deleted_at" = EXCLUDED."deleted_at", "title" = EXCLUDED."title", '
        '"tags" = EXCLUDED."tags"',
      );
      expect(s.params, [
        '7',
        at,
        null,
        'Hi',
        ['a'],
      ]);
    });

    test('delete is soft when a deleted_at column is configured', () {
      expect(
        pg.delete('posts', soft, delete).sql,
        r'UPDATE "posts" SET "deleted_at" = $1, "updated_at" = $2 WHERE "id" = $3',
      );
      expect(
        pg.delete('posts', const SqlTable(), delete).sql,
        r'DELETE FROM "posts" WHERE "id" = $1',
      );
    });

    test('quotes identifiers safely', () {
      expect(pg.quote('we"ird'), '"we""ird"');
    });

    test('rows become changes; soft-deleted rows become deletes', () {
      final live = pg.rowToChange({
        'id': 7,
        'updated_at': at,
        'deleted_at': null,
        'title': 'Hi',
      }, soft);
      expect(live.id, '7');
      expect(live.data, {'title': 'Hi'});
      final gone = pg.rowToChange({
        'id': 7,
        'updated_at': at,
        'deleted_at': at,
        'title': 'Hi',
      }, soft);
      expect(gone.isDelete, isTrue);
    });
  });

  group('MySQL', () {
    const my = MySqlDialect();

    test('upsert uses ON DUPLICATE KEY and JSON-encodes nested values', () {
      final s = my.upsert('posts', const SqlTable(), upsert);
      expect(
        s.sql,
        'INSERT INTO `posts` (`id`, `updated_at`, `title`, `tags`) VALUES (?, ?, ?, ?) '
        'ON DUPLICATE KEY UPDATE `updated_at` = VALUES(`updated_at`), '
        '`title` = VALUES(`title`), `tags` = VALUES(`tags`)',
      );
      expect(s.params, ['7', at, 'Hi', '["a"]']);
    });

    test('pull uses ? placeholders and UTC timestamps', () {
      final local = Change.delete(id: '1', updatedAt: at.toLocal());
      final s = my.pull(
        'posts',
        const SqlTable(),
        SqlDialect.encodeCursor(local),
        5,
      );
      expect(
        s.sql,
        'SELECT * FROM `posts` WHERE (`updated_at`, `id`) > (?, ?) ORDER BY `updated_at`, `id` LIMIT 5',
      );
      expect((s.params.first as DateTime).isUtc, isTrue);
    });
  });
}
