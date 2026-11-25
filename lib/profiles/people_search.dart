import 'profile.dart';

/// The [profiles] matching what's typed in a people search, ignoring case
/// and surrounding spaces: names starting with [query] first, then names
/// with a word starting with it, then names containing it, then people
/// whose job title or department contains it. Each group keeps the given
/// order. An empty query matches everyone.
List<Profile> searchPeople(Iterable<Profile> profiles, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [...profiles];
  final groups = [<Profile>[], <Profile>[], <Profile>[], <Profile>[]];
  for (final p in profiles) {
    final name = p.fullName.toLowerCase();
    if (name.startsWith(q)) {
      groups[0].add(p);
    } else if (name.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) {
      groups[1].add(p);
    } else if (name.contains(q)) {
      groups[2].add(p);
    } else if (p.jobTitle.toLowerCase().contains(q) ||
        p.department.toLowerCase().contains(q)) {
      groups[3].add(p);
    }
  }
  return [for (final g in groups) ...g];
}
