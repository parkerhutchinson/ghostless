import 'dart:io';

import 'package:codename/app_theme.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/tasks/form_buttons.dart';
import 'package:codename/tasks/labels_sheet.dart';
import 'package:codename/tasks/project_labels.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  testWidgets('backing out of a deletion calls it off, so a later Save '
      'saves without asking', (tester) async {
    final store = LocalStore.inMemory();
    final projects = ProjectRepository(store);
    final tasks = TaskRepository(store, Directory.systemTemp.createTempSync());
    final pid = projects.create('Acme').id;
    projects.addLabels(pid, ['Bug', 'Docs'], colors: {'bug': 2, 'docs': 3});
    tasks.create(originId: pid, title: 'T', tags: ['Bug']);
    final labels = ProjectLabels(projects, tasks, pid);
    final changes = LabelChanges();
    var closed = false;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: LabelsSheet(
            labels: labels,
            changes: changes,
            projectName: 'Acme',
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    // Delete Bug (on a task): Save asks first.
    await tester.tap(find.byTooltip('Delete label').first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Bug"?'), findsOneWidget);

    // ←: no deletion after all; Bug is back in the list.
    await tester.tap(find.byType(FormCloseButton));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Bug"?'), findsNothing);
    expect(find.byTooltip('Delete label'), findsNWidgets(2));

    // Recolor Docs and save: no question, nothing deleted.
    await tester.tap(find.byTooltip('Color').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Color 6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete'), findsNothing);
    expect(closed, isTrue);
    expect(labels.all(), containsAll(['Bug', 'Docs']));
    expect(labels.colorOf('Docs'), 5);
    expect(changes.deleted, isEmpty);
  });
}
