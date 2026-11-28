import 'package:codename/developer/database_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the rows, biggest first, and adds them up', () {
    final stats = databaseStatsFrom(
      '9000000',
      [
        ['comments', 5, 8192],
        ['tasks', 900, '2000000'],
        ['activity', 90, 8192],
      ],
      [
        ['files', 3, 1500],
        ['codename', '40', 30000000],
      ],
    );
    expect(stats.databaseBytes, 9000000);
    expect(
      [for (final t in stats.tables) t.name],
      ['tasks', 'activity', 'comments'],
    );
    expect(stats.rows, 995);
    expect(stats.tableBytes, 2016384);
    expect([for (final b in stats.buckets) b.name], ['codename', 'files']);
    expect(stats.files, 43);
    expect(stats.storageBytes, 30001500);
  });

  test('copes with nothing and with odd values', () {
    final stats = databaseStatsFrom(null, const [], const []);
    expect(stats.databaseBytes, 0);
    expect(stats.rows, 0);
    expect(stats.storageBytes, 0);
    expect(databaseStatsFrom(1.6, const [], const []).databaseBytes, 2);
  });
}
