import 'package:codename/developer/service_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a file key drops the org folder in front', () {
    expect(fileKey('tasks/a.png'), 'tasks/a.png');
    expect(fileKey('org1/tasks/a.png'), 'tasks/a.png');
    expect(fileKey('a.png'), 'a.png');
  });

  test('orphans: stored files no record refers to, biggest first', () {
    final referenced = referencedKeys([
      ['tasks', 'a.png'],
      ['profiles', 'me.jpg'],
      ['backgrounds', null], // a profile with no background image
      ['backgrounds', ''],
    ]);
    expect(referenced, {'tasks/a.png', 'profiles/me.jpg'});
    final orphans = orphanFiles([
      (bucket: 'b', path: 'tasks/a.png', bytes: 10),
      (bucket: 'b', path: 'org1/profiles/me.jpg', bytes: 20),
      (bucket: 'b', path: 'tasks/old.png', bytes: 5),
      (
        bucket: 'b',
        path: 'profiles/a.png',
        bytes: 50,
      ), // same name, other folder
    ], referenced);
    expect(
      [for (final o in orphans) o.path],
      ['profiles/a.png', 'tasks/old.png'],
    );
  });

  test('connections add up per user, most first', () {
    final stats = connectionStatsFrom('60', '3', [
      ['postgres', 1],
      [null, 5],
      ['authenticator', '4'],
    ]);
    expect(stats.max, 60);
    expect(stats.reserved, 3);
    expect(stats.inUse, 10);
    expect(
      [for (final u in stats.byUser) (u.user, u.count)],
      [('Postgres itself', 5), ('authenticator', 4), ('postgres', 1)],
    );
  });
}
