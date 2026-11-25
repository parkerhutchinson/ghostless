import 'package:codename/profiles/people_search.dart';
import 'package:codename/profiles/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026);
  Profile person(String name, {String job = '', String dept = ''}) => Profile(
    id: name,
    name: name,
    jobTitle: job,
    department: dept,
    createdAt: created,
  );
  final people = [
    person('Maya Okafor', job: 'Staff Engineer', dept: 'Engineering'),
    person('Amara Mensah', job: 'Product Manager', dept: 'Product'),
    person('Tom Becker', job: 'QA Lead', dept: 'Engineering'),
    person('Marco Diaz'),
  ];
  List<String> find(String q) => [
    for (final p in searchPeople(people, q)) p.name,
  ];

  test('everyone for an empty query, in order', () {
    expect(find('  '), [
      'Maya Okafor',
      'Amara Mensah',
      'Tom Becker',
      'Marco Diaz',
    ]);
  });

  test('name starts, then a word starts, then contains', () {
    // "ma": Maya and Marco start with it; Amara and Mensah contain it.
    expect(find('ma'), ['Maya Okafor', 'Marco Diaz', 'Amara Mensah']);
    expect(find('becker'), ['Tom Becker']);
    expect(find('KAF'), ['Maya Okafor']);
  });

  test('job title and department, after names', () {
    expect(find('engineer'), ['Maya Okafor', 'Tom Becker']);
    expect(find('product'), ['Amara Mensah']);
    expect(find('nobody'), isEmpty);
  });
}
