import 'package:codename/projects/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime(2026);
  Project p(String name) => Project(id: name, name: name, createdAt: created);
  final projects = [p('Home'), p('Work'), p('Homework'), p('Side hustle')];
  List<String> names(String q) =>
      projectSuggestions(projects, q).map((p) => p.name).toList();

  test('empty or blank query offers every project, in order', () {
    expect(names(''), ['Home', 'Work', 'Homework', 'Side hustle']);
    expect(names('   '), ['Home', 'Work', 'Homework', 'Side hustle']);
  });

  test('names starting with the query come before ones containing it', () {
    expect(names('work'), ['Work', 'Homework']);
    expect(names('ho'), ['Home', 'Homework']);
  });

  test('ignores case and surrounding spaces', () {
    expect(names('  SIDE '), ['Side hustle']);
  });

  test('no match gives nothing', () {
    expect(names('xyz'), isEmpty);
  });
}
