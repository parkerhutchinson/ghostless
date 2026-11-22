import 'dart:io';

import 'package:codename/projects/project_repository.dart';
import 'package:codename/tasks/project_labels.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late ProjectRepository projects;
  late TaskRepository tasks;
  late String pid;
  late ProjectLabels labels;

  setUp(() {
    final store = LocalStore.inMemory();
    projects = ProjectRepository(store);
    tasks = TaskRepository(store, Directory.systemTemp.createTempSync());
    pid = projects.create('Acme').id;
    projects.addLabels(pid, ['Bug', 'Docs'], colors: {'bug': 2});
    labels = ProjectLabels(projects, tasks, pid);
  });

  test('all lists the project\'s labels and its tasks\', sorted', () {
    tasks.create(originId: pid, title: 'T', tags: ['api', 'bug']);
    expect(labels.all(), ['api', 'Bug', 'Docs']);
    expect(labels.usage('BUG'), 1);
  });

  test('rename changes the project, its color and its tasks', () {
    final t = tasks.create(originId: pid, title: 'T', tags: ['Bug', 'x']);
    final changes = LabelChanges();
    expect(labels.rename('Bug', 'Defect', changes), isTrue);
    expect(projects.get(pid)!.labels, ['Defect', 'Docs']);
    expect(projects.get(pid)!.labelColors, {'defect': 2});
    expect(tasks.get(t.id)!.tags, ['Defect', 'x']);
    expect(changes.applyTo(['bug', 'x']), ['Defect', 'x']);
  });

  test('renaming onto another label merges them', () {
    final t = tasks.create(originId: pid, title: 'T', tags: ['Bug', 'Docs']);
    labels.rename('Bug', 'docs', LabelChanges());
    expect(projects.get(pid)!.labels, ['docs']);
    expect(tasks.get(t.id)!.tags, ['docs']);
  });

  test('a blank name changes nothing', () {
    expect(labels.rename('Bug', '  ', LabelChanges()), isFalse);
    expect(projects.get(pid)!.labels, ['Bug', 'Docs']);
  });

  test('delete removes it from the project and its tasks', () {
    final t = tasks.create(originId: pid, title: 'T', tags: ['Bug', 'x']);
    final changes = LabelChanges();
    labels.delete('bug', changes);
    expect(projects.get(pid)!.labels, ['Docs']);
    expect(projects.get(pid)!.labelColors, isEmpty);
    expect(tasks.get(t.id)!.tags, ['x']);
    expect(changes.applyTo(['Bug', 'x']), ['x']);
  });

  test('renamed then deleted: gone from the form too', () {
    final changes = LabelChanges();
    labels.rename('Bug', 'Defect', changes);
    labels.delete('Defect', changes);
    expect(changes.applyTo(['Bug', 'Docs']), ['Docs']);
  });

  test('setColor recolors a label', () {
    labels.setColor('Docs', 5);
    expect(projects.get(pid)!.labelColors['docs'], 5);
  });
}
