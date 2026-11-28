import 'package:codename/files/storage_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds up each kind, counts a shared file once, skips missing', () {
    final stats = storageStats([
      (kind: StoredKind.cardImages, name: 'a.png', size: 100),
      (kind: StoredKind.cardImages, name: 'a.png', size: 100), // two tasks
      (kind: StoredKind.cardImages, name: 'b.png', size: 50),
      (kind: StoredKind.attachments, name: 'c.pdf', size: 1000),
      (kind: StoredKind.profilePhotos, name: 'd.jpg', size: null), // not here
    ]);
    expect(stats.bytes, 1150);
    expect(stats.missing, 1);
    expect([for (final k in stats.kinds) (k.kind, k.files, k.bytes)], [
      (StoredKind.cardImages, 2, 150),
      (StoredKind.attachments, 1, 1000),
      (StoredKind.profilePhotos, 0, 0),
      (StoredKind.backgrounds, 0, 0),
    ]);
  });

  test('formats sizes for people', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(13002342), '12.4 MB');
    expect(formatBytes(150 * 1024 * 1024), '150 MB');
    expect(formatBytes(2254857830), '2.1 GB');
  });
}
