import 'package:postgres/postgres.dart' as pg;

/// Sign-in accounts (Supabase Auth's users).
typedef AccountStats = ({
  int total,

  /// Signed up in the last 7 days.
  int newThisWeek,

  /// Signed in within the last 7 and 30 days.
  int active7,
  int active30,
});

/// A business org: how many people are in it and invites still open.
typedef BusinessOrg = ({String name, int members, int openInvites});

typedef OrgStats = ({int personal, List<BusinessOrg> businesses});

/// One synced table's recent activity.
typedef TableActivity = ({
  String name,

  /// Rows not deleted.
  int live,

  /// Rows changed (written by an app) in the last 24 hours and 7 days.
  int changed24h,
  int changed7d,

  /// Deleted rows still kept, so the delete syncs to every Mac.
  int deleted,
});

/// Database connections in use, against the most allowed.
typedef ConnectionStats = ({
  int max,

  /// Kept back for administrators: never available to apps.
  int reserved,
  int inUse,

  /// Who holds them (the database user), most first.
  List<({String user, int count})> byUser,
});

/// A file in storage that no record refers to any more.
typedef StoredObject = ({String bucket, String path, int bytes});

/// Everything else the Developer view shows about the service. A part is
/// null when the database doesn't have what it needs (no Supabase Auth,
/// no orgs tables, no Storage).
typedef ServiceStats = ({
  AccountStats? accounts,
  OrgStats? orgs,
  List<TableActivity> activity,
  ConnectionStats connections,
  List<StoredObject>? orphans,
});

/// A number from the driver: bigint and numeric come as ints or text.
int _int(Object? v) => switch (v) {
  final int n => n,
  final num n => n.round(),
  final String s => num.tryParse(s)?.round() ?? 0,
  _ => 0,
};

/// Where a stored file sits, without the org folder in front (if any):
/// `tasks/a.png` for `org1/tasks/a.png` or `tasks/a.png`.
String fileKey(String path) {
  final parts = path.split('/');
  return parts.length < 2 ? path : '${parts[parts.length - 2]}/${parts.last}';
}

/// The [objects] in storage that no record refers to: [referenced] holds
/// `folder/name` keys (`tasks/a.png`). Biggest first, then by path.
List<StoredObject> orphanFiles(
  Iterable<StoredObject> objects,
  Set<String> referenced,
) =>
    [
      for (final o in objects)
        if (!referenced.contains(fileKey(o.path))) o,
    ]..sort(
      (a, b) => a.bytes != b.bytes
          ? b.bytes.compareTo(a.bytes)
          : a.path.compareTo(b.path),
    );

/// The file keys the records refer to (not deleted ones): tasks' images
/// and attachments, profile photos, background images (the one showing
/// and the one last uploaded). Each row is (folder, name).
Set<String> referencedKeys(Iterable<List<Object?>> rows) => {
  for (final r in rows)
    if (r[1] case final String name when name.isNotEmpty) '${r[0]}/$name',
};

/// Connection rows as [ConnectionStats]: settings (max, reserved) and
/// (user, count) per user.
ConnectionStats connectionStatsFrom(
  Object? max,
  Object? reserved,
  Iterable<List<Object?>> byUser,
) {
  final users =
      [
        for (final r in byUser)
          (user: '${r[0] ?? 'Postgres itself'}', count: _int(r[1])),
      ]..sort(
        (a, b) => a.count != b.count
            ? b.count.compareTo(a.count)
            : a.user.compareTo(b.user),
      );
  return (
    max: _int(max),
    reserved: _int(reserved),
    inUse: users.fold(0, (n, u) => n + u.count),
    byUser: users,
  );
}

Future<bool> _exists(pg.Connection c, String relation) async =>
    (await c.execute(
      pg.Sql.named('select to_regclass(@r) is not null'),
      parameters: {'r': relation},
    )).first.first ==
    true;

/// Asks the database on [c] for everything in [ServiceStats]. Read only.
Future<ServiceStats> fetchServiceStats(pg.Connection c) async {
  AccountStats? accounts;
  if (await _exists(c, 'auth.users')) {
    final r = (await c.execute('''
      select count(*),
        count(*) filter (where created_at > now() - interval '7 days'),
        count(*) filter (where last_sign_in_at > now() - interval '7 days'),
        count(*) filter (where last_sign_in_at > now() - interval '30 days')
      from auth.users
    ''')).first;
    accounts = (
      total: _int(r[0]),
      newThisWeek: _int(r[1]),
      active7: _int(r[2]),
      active30: _int(r[3]),
    );
  }

  OrgStats? orgs;
  if (await _exists(c, 'public.orgs')) {
    final personal = (await c.execute(
      "select count(*) from public.orgs where kind = 'personal'",
    )).first.first;
    final businesses = await c.execute('''
      select o.name,
        (select count(*) from public.org_members m where m.org_id = o.id),
        (select count(*) from public.org_invites i
          where i.org_id = o.id and i.accepted_at is null)
      from public.orgs o
      where o.kind = 'business'
      order by o.name
    ''');
    orgs = (
      personal: _int(personal),
      businesses: [
        for (final r in businesses)
          (name: '${r[0]}', members: _int(r[1]), openInvites: _int(r[2])),
      ],
    );
  }

  // The synced tables: the ones with the sync's columns.
  final synced = await c.execute('''
    select table_name from information_schema.columns
    where table_schema = 'public' and column_name in ('updated_at', 'deleted_at')
    group by table_name having count(*) = 2
    order by table_name
  ''');
  final activity = <TableActivity>[];
  for (final row in synced) {
    final table = '${row[0]}'.replaceAll('"', '""');
    final r = (await c.execute('''
      select count(*) filter (where deleted_at is null),
        count(*) filter (where updated_at > now() - interval '24 hours'),
        count(*) filter (where updated_at > now() - interval '7 days'),
        count(*) filter (where deleted_at is not null)
      from public."$table"
    ''')).first;
    activity.add((
      name: '${row[0]}',
      live: _int(r[0]),
      changed24h: _int(r[1]),
      changed7d: _int(r[2]),
      deleted: _int(r[3]),
    ));
  }

  final settings = (await c.execute(
    "select current_setting('max_connections'), "
    "current_setting('superuser_reserved_connections')",
  )).first;
  final byUser = await c.execute(
    'select usename, count(*) from pg_stat_activity group by usename',
  );
  final connections = connectionStatsFrom(settings[0], settings[1], byUser);

  List<StoredObject>? orphans;
  if (await _exists(c, 'storage.objects')) {
    final referenced = referencedKeys(
      await c.execute(r'''
      select 'tasks', jsonb_array_elements_text(images)
        from public.tasks where deleted_at is null
          and jsonb_typeof(images) = 'array'
      union all
      select 'tasks', a->>'file'
        from public.tasks, jsonb_array_elements(attachments) a
        where deleted_at is null and jsonb_typeof(attachments) = 'array'
      union all
      select 'profiles', "imageFile" from public.profiles
        where deleted_at is null
      union all
      select 'backgrounds', theme->'background'->>'file' from public.profiles
        where deleted_at is null
      union all
      select 'backgrounds', theme->>'backgroundUpload' from public.profiles
        where deleted_at is null
    '''),
    );
    final objects = await c.execute('''
      select bucket_id, name, coalesce((metadata->>'size')::bigint, 0)
      from storage.objects
    ''');
    orphans = orphanFiles([
      for (final r in objects)
        (bucket: '${r[0]}', path: '${r[1]}', bytes: _int(r[2])),
    ], referenced);
  }

  return (
    accounts: accounts,
    orgs: orgs,
    activity: activity,
    connections: connections,
    orphans: orphans,
  );
}
