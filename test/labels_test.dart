import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/tasks/label_colors.dart';
import 'package:codename/tasks/label_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  testWidgets('a label is in its own project\'s color, not another\'s', (
    tester,
  ) async {
    final seen = <String, Color>{};
    await tester.pumpWidget(
      LabelColors(
        byProject: const {
          'a': {'bug': 3},
          'b': {'bug': 5},
        },
        child: Builder(
          builder: (context) {
            for (final id in ['a', 'b', 'c']) {
              seen[id] = LabelColors.of(context, 'Bug', id);
            }
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen['a'], labelPalette[3]);
    expect(seen['b'], labelPalette[5]);
    // Not picked there: its default, not another project's pick.
    expect(seen['c'], labelPalette[defaultLabelColor('Bug')]);
  });

  group('labelOptions', () {
    const known = ['Bug', 'Design', 'design-review', 'Docs'];

    test('nothing typed lists every label not on the task', () {
      final o = labelOptions('', known: known, chosen: ['Docs']);
      expect(o.map((o) => o.label), ['Bug', 'Design', 'design-review']);
      expect(o.any((o) => o.isNew), isFalse);
    });

    test('typing offers Create first, then matches (ignoring case)', () {
      final o = labelOptions('des', known: known, chosen: []);
      expect(o.first, (label: 'des', isNew: true));
      expect(o.skip(1).map((o) => o.label), ['Design', 'design-review']);
    });

    test('an existing label (any case) is not offered to create; the exact '
        'match comes first', () {
      final o = labelOptions('design', known: known, chosen: []);
      expect(o.any((o) => o.isNew), isFalse);
      expect(o.map((o) => o.label), ['Design', 'design-review']);
    });

    test('a label already on the task is neither created nor listed', () {
      expect(labelOptions('bug', known: known, chosen: ['Bug']), isEmpty);
    });
  });

  group('project labels', () {
    late ProjectRepository projects;
    setUp(() => projects = ProjectRepository(LocalStore.inMemory()));

    test('addLabels keeps new ones only, ignoring case and blanks', () {
      final p = projects.create('Acme');
      projects.addLabels(p.id, ['Bug', 'ui']);
      projects.addLabels(p.id, ['bug', ' ', 'Docs', 'UI']);
      expect(projects.get(p.id)!.labels, ['Bug', 'ui', 'Docs']);
    });

    test('a new label keeps the color picked for it; the first one sticks', () {
      final p = projects.create('Acme');
      projects.addLabels(p.id, ['Bug'], colors: {'bug': 3});
      projects.addLabels(p.id, ['bug', 'Docs'], colors: {'bug': 5});
      expect(projects.get(p.id)!.labelColors, {'bug': 3});
      expect(projects.get(p.id)!.labels, ['Bug', 'Docs']);
    });

    test('label colors round-trip through JSON', () {
      final p = projects.create('Acme').copyWith(labelColors: {'bug': 2});
      expect(Project.fromJson(p.id, p.toJson()).labelColors, {'bug': 2});
      expect(
        Project.fromJson('x', {
          'labelColors': {'a': 'x'},
        }).labelColors,
        isEmpty,
      );
    });

    test('16 hues, and the pickers show each exactly once', () {
      expect(labelPalette, hasLength(16));
      expect(labelPalette.toSet(), hasLength(16));
      expect(labelPickerOrder.toSet(), Set.of(List.generate(16, (i) => i)));
      expect(projectColorOrder.toSet(), Set.of(List.generate(18, (i) => i)));
    });

    test('a label without a picked color has a steady default', () {
      expect(defaultLabelColor('Design'), defaultLabelColor('design'));
      expect(defaultLabelColor('Design'), inInclusiveRange(0, 7));
    });

    test('labels round-trip through JSON; old projects have none', () {
      final p = projects.create('Acme').copyWith(labels: ['a', 'b']);
      expect(Project.fromJson(p.id, p.toJson()).labels, ['a', 'b']);
      expect(Project.fromJson('x', {'name': 'Old'}).labels, isEmpty);
    });
  });
}
