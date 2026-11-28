/// The kinds of file the app keeps, in the order the Company page lists
/// them.
enum StoredKind {
  cardImages('Card images'),
  attachments('Attachments'),
  profilePhotos('Profile photos'),
  backgrounds('Backgrounds');

  const StoredKind(this.label);
  final String label;
}

/// One file a record refers to, and its size on this Mac in bytes (null
/// when it isn't here: not fetched from storage yet, or missing).
typedef StoredFile = ({StoredKind kind, String name, int? size});

/// How much one kind of file takes up.
typedef KindUsage = ({StoredKind kind, int files, int bytes});

/// What the files take up: per kind (every kind, in [StoredKind] order,
/// even with none), and in all. A file listed twice (an image on two
/// tasks) counts once. Files not on this Mac count in [missing], not in
/// the sizes.
typedef StorageStats = ({List<KindUsage> kinds, int bytes, int missing});

StorageStats storageStats(Iterable<StoredFile> files) {
  final seen = <(StoredKind, String)>{};
  final count = {for (final k in StoredKind.values) k: 0};
  final bytes = {for (final k in StoredKind.values) k: 0};
  var missing = 0;
  for (final f in files) {
    if (!seen.add((f.kind, f.name))) continue;
    if (f.size case final size?) {
      count[f.kind] = count[f.kind]! + 1;
      bytes[f.kind] = bytes[f.kind]! + size;
    } else {
      missing++;
    }
  }
  return (
    kinds: [
      for (final k in StoredKind.values)
        (kind: k, files: count[k]!, bytes: bytes[k]!),
    ],
    bytes: bytes.values.fold(0, (a, b) => a + b),
    missing: missing,
  );
}

/// [bytes] for people: "0 B", "512 B", "1.5 KB", "12.4 MB", "2.1 GB" (1 KB
/// = 1024 bytes; one decimal below 100, none from 100 up).
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final shown = value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$shown ${units[unit]}';
}
