import 'package:flutter/services.dart';

import 'support/finders.dart';

import 'dart:io';

import 'package:codename/projects/project.dart';
import 'package:codename/tasks/task.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:codename/tasks/task_card.dart';
import 'package:codename/tasks/task_editor.dart';
import 'package:codename/tasks/tasks_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

const pid = 'work';
final project = Project(id: pid, name: 'Work', createdAt: DateTime.utc(2026));

void main() {
  late Directory dir;
  late LocalStore store;
  late TaskRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tasks_test');
    store = LocalStore.inMemory();
    repo = TaskRepository(store, dir);
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  List<String> titles(String status) => [
    for (final t in repo.current().where((t) => t.status == status)) t.title,
  ];

  group('TaskRepository', () {
    test('subtasks round-trip in order; old records have none', () {
      final t = repo.create(
        originId: pid,
        title: 'Trip',
        subtasks: const [
          Subtask(id: 'a', title: 'Book flights'),
          Subtask(id: 'b', title: 'Pack', done: true),
        ],
      );
      expect(repo.get(t.id)!.subtasks, const [
        Subtask(id: 'a', title: 'Book flights'),
        Subtask(id: 'b', title: 'Pack', done: true),
      ]);
      store.put('tasks', 'old', {'title': 'Old', 'originId': pid});
      expect(repo.get('old')!.subtasks, isEmpty);
    });

    test(
      'the assignee round-trips, can be cleared, and old records have none',
      () {
        final t = repo.create(originId: pid, title: 'Mine', assigneeId: 'p1');
        expect(repo.get(t.id)!.assigneeId, 'p1');
        repo.save(repo.get(t.id)!.copyWith(title: 'Renamed'));
        expect(repo.get(t.id)!.assigneeId, 'p1', reason: 'kept when not given');
        repo.save(repo.get(t.id)!.copyWith(assigneeId: null));
        expect(repo.get(t.id)!.assigneeId, isNull);
        store.put('tasks', 'old', {'title': 'Old', 'originId': pid});
        expect(repo.get('old')!.assigneeId, isNull);
        store.put('tasks', 'blank', {'title': 'B', 'assigneeId': ''});
        expect(repo.get('blank')!.assigneeId, isNull);
      },
    );

    test('assign sets and clears the assignee, leaving the rest', () {
      final t = repo.create(originId: pid, title: 'T', tags: ['x']);
      repo.assign(t.id, 'p2');
      expect(repo.get(t.id)!.assigneeId, 'p2');
      expect(repo.get(t.id)!.tags, ['x']);
      repo.assign(t.id, null);
      expect(repo.get(t.id)!.assigneeId, isNull);
      repo.assign('missing', 'p2'); // no-op
    });

    test('duplicating keeps the assignee', () async {
      final t = repo.create(originId: pid, title: 'T', assigneeId: 'p1');
      expect((await repo.duplicate(t.id))!.assigneeId, 'p1');
    });

    test('duplicate copies a task just below the original', () async {
      repo.create(originId: pid, title: 'A');
      final b = repo.create(
        originId: pid,
        title: 'B',
        tags: ['x'],
        subtasks: const [Subtask(id: 's', title: 'Step')],
      );
      repo.create(originId: pid, title: 'C');
      final copy = (await repo.duplicate(b.id))!;
      expect(titles('todo'), ['A', 'B', 'B (copy)', 'C']);
      expect(copy.tags, ['x']);
      expect(copy.subtasks.single.title, 'Step');
      expect(copy.subtasks.single.id, isNot('s'));
      expect(copy.id, isNot(b.id));
    });

    test('subtasks can be checked off and reordered', () {
      final t = repo.create(
        originId: pid,
        title: 'Trip',
        subtasks: const [
          Subtask(id: 'a', title: 'A'),
          Subtask(id: 'b', title: 'B'),
          Subtask(id: 'c', title: 'C'),
        ],
      );
      repo.toggleSubtask(t.id, 'b');
      expect(repo.get(t.id)!.subtasks[1].done, isTrue);
      repo.moveSubtask(t.id, 'c', 0);
      expect([for (final s in repo.get(t.id)!.subtasks) s.id], ['c', 'a', 'b']);
      repo.moveSubtask(t.id, 'c', 99);
      expect([for (final s in repo.get(t.id)!.subtasks) s.id], ['a', 'b', 'c']);
    });

    test('new tasks go to the bottom of their column', () {
      repo.create(originId: pid, title: 'A');
      repo.create(originId: pid, title: 'B');
      repo.create(originId: pid, title: 'C', status: 'doing');
      expect(titles('todo'), ['A', 'B']);
      expect(titles('doing'), ['C']);
    });

    test(
      'move places a task between neighbours, across and within columns',
      () {
        final a = repo.create(originId: pid, title: 'A');
        repo.create(originId: pid, title: 'B');
        repo.create(originId: pid, title: 'X', status: 'doing');
        repo.create(originId: pid, title: 'Y', status: 'doing');

        repo.move(a.id, 'doing', 1); // between X and Y
        expect(titles('todo'), ['B']);
        expect(titles('doing'), ['X', 'A', 'Y']);

        repo.move(a.id, 'doing', 0); // to the top
        expect(titles('doing'), ['A', 'X', 'Y']);

        repo.move(a.id, 'doing', 99); // past the end clamps to the bottom
        expect(titles('doing'), ['X', 'Y', 'A']);
      },
    );

    test('tasks dismissed by the earlier version load as done', () {
      store.put('tasks', 'old', {
        'title': 'Old',
        'status': 'doing',
        'dismissed': true,
      });
      expect(repo.get('old')!.status, 'done');
    });

    test('images are copied in and deleted with the task', () async {
      final source = File('${dir.path}/photo.PNG')..writeAsBytesSync([1, 2, 3]);
      final name = await repo.addImage(source.path);
      expect(name, endsWith('.png'));
      expect(repo.imageFile(name).readAsBytesSync(), [1, 2, 3]);

      final task = repo.create(
        originId: pid,
        title: 'With image',
        images: [name],
      );
      repo.delete(task.id);
      expect(repo.imageFile(name).existsSync(), isFalse);
      expect(source.existsSync(), isTrue, reason: 'the original is untouched');
    });

    test('keepImages leaves files until deleteUnusedImages runs', () async {
      final source = File('${dir.path}/a.png')..writeAsBytesSync([1]);
      final kept = await repo.addImage(source.path);
      final used = await repo.addImage(source.path);
      final gone = repo.create(originId: pid, title: 'Deleted', images: [kept]);
      repo.create(originId: pid, title: 'Still here', images: [used]);

      repo.delete(gone.id, keepImages: true);
      expect(repo.imageFile(kept).existsSync(), isTrue);

      repo.deleteUnusedImages();
      expect(repo.imageFile(kept).existsSync(), isFalse);
      expect(repo.imageFile(used).existsSync(), isTrue);
    });

    test('tags, description and images round-trip through the store', () {
      final t = repo.create(
        originId: pid,
        title: 'T',
        description: 'details',
        tags: ['design', 'urgent'],
        images: ['a.png'],
      );
      final loaded = repo.get(t.id)!;
      expect(loaded.description, 'details');
      expect(loaded.tags, ['design', 'urgent']);
      expect(loaded.images, ['a.png']);
    });

    test('records with missing or unknown fields still load', () {
      store.put('tasks', 'x', {'title': 'Synced in', 'status': 'archived'});
      final t = repo.get('x')!;
      // Kept as stored: a board shows a status it has no column for in its
      // first column (see Project.columnFor).
      expect(t.status, 'archived');
      expect(t.projectIds, isEmpty, reason: 'no project yet: an orphan');
      expect(t.originId, '');
      expect(repo.orphans({pid}).single.id, 'x');
      expect(t.tags, isEmpty);
    });

    test('records from before origins use their first project as origin', () {
      store.put('tasks', 'multi', {
        'title': 'Multi',
        'projectIds': ['first', 'second'],
      });
      final t = repo.get('multi')!;
      expect(t.originId, 'first');
      expect(t.multiHomes, ['second']);
    });

    test('the origin is always one of its projects', () {
      store.put('tasks', 'odd', {
        'title': 'Odd',
        'originId': 'home',
        'projectIds': ['away'],
      });
      expect(repo.get('odd')!.projectIds, ['home', 'away']);
    });

    test('records from when a task had a single project still load', () {
      store.put('tasks', 'old', {'title': 'Old', 'projectId': pid});
      expect(repo.get('old')!.projectIds, [pid]);
      expect(repo.get('old')!.originId, pid, reason: 'its only project');
      expect(repo.inProject(pid).single.id, 'old');
    });
  });

  group('TasksPage', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: TasksPage(
              repo: repo,
              title: 'Work',
              projectId: pid,
              projects: [project],
              projectRepo: ProjectRepository(store),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows a column per status with its tasks', (tester) async {
      repo.create(originId: pid, title: 'Write spec', tags: ['docs']);
      repo.create(originId: pid, title: 'Build it', status: 'doing');
      await pumpPage(tester);

      for (final c in defaultColumns) {
        expect(text(c.title), findsOneWidget);
      }
      expect(text('Write spec'), findsOneWidget);
      expect(text('docs'), findsOneWidget);
      expect(text('Build it'), findsOneWidget);
    });

    testWidgets('the hover delete button deletes, and Undo restores the task', (
      tester,
    ) async {
      final source = File('${dir.path}/pic.png')..writeAsBytesSync([1]);
      final image = await tester.runAsync(() => repo.addImage(source.path));
      final task = repo.create(
        originId: pid,
        title: 'Delete me',
        images: [image!],
      );
      await pumpPage(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(text('Delete me')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Task options'));
      await tester.pumpAndSettle();
      await tester.tap(text('Delete'));
      await tester.pumpAndSettle();
      expect(text('Delete me'), findsNothing);
      expect(repo.get(task.id), isNull);
      expect(text('"Delete me" deleted'), findsOneWidget);
      expect(
        repo.imageFile(image).existsSync(),
        isTrue,
        reason: 'kept for undo',
      );

      await tester.tap(text('Undo'));
      await tester.pumpAndSettle();
      expect(text('Delete me'), findsOneWidget);
      expect(repo.get(task.id)!.images, [image]);
      expect(repo.imageFile(image).existsSync(), isTrue);
    });

    testWidgets('deleting from the editor also offers undo', (tester) async {
      repo.create(originId: pid, title: 'Edit then delete');
      await pumpPage(tester);
      await tester.tap(text('Edit then delete'));
      await tester.pumpAndSettle();
      // Delete is in the form's ⋯ menu.
      await tester.tap(find.byTooltip('Task options').last);
      await tester.pumpAndSettle();
      await tester.tap(text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.current(), isEmpty);
      expect(text('"Edit then delete" deleted'), findsOneWidget);
    });

    testWidgets('dragging a card into another column moves it', (tester) async {
      final task = repo.create(originId: pid, title: 'Drag me');
      await pumpPage(tester);

      final start = tester.getCenter(text('Drag me'));
      final target = tester.getCenter(text('No tasks').last); // "Done" is empty
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(repo.get(task.id)!.status, 'done');
    });

    testWidgets('creating a task through the editor', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Fresh',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Add label, press Enter'),
        'ui,',
      );
      await tester.pump();
      await tester.tap(text('Create task'));
      await tester.pumpAndSettle();

      final created = repo.current().single;
      expect(created.title, 'Fresh');
      expect(created.tags, ['ui']);
      expect(text('Fresh'), findsOneWidget);
    });

    testWidgets('Enter adds a typed label; saving keeps it on the project', (
      tester,
    ) async {
      store.put('projects', pid, project.toJson());
      await pumpPage(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Labelled',
      );
      final field = find.widgetWithText(TextField, 'Add label, press Enter');
      await tester.tap(field);
      await tester.enterText(field, 'Design');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(text('Design'), findsOneWidget, reason: 'chip added');

      await tester.tap(text('Create task'));
      await tester.pumpAndSettle();
      expect(repo.current().single.tags, ['Design']);
      expect(ProjectRepository(store).get(pid)?.labels, ['Design']);
    });

    testWidgets('Edit labels renames a label on the project, its tasks and '
        'the open form', (tester) async {
      store.put('projects', pid, project.toJson());
      final other = repo.create(originId: pid, title: 'Other', tags: ['Bug']);
      final t = repo.create(originId: pid, title: 'T', tags: ['Bug']);
      await pumpPage(tester);
      await tester.tap(text('T'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit labels'));
      await tester.pumpAndSettle();
      // The name field is the swatch's height.
      final field = find.widgetWithText(TextField, 'Bug');
      final swatch = find.descendant(
        of: find.byTooltip('Color'),
        matching: find.byType(Container),
      );
      expect(
        tester.getSize(field.first).height,
        tester.getSize(swatch.first).height,
      );

      // Closing drops the edit.
      await tester.enterText(find.widgetWithText(TextField, 'Bug'), 'Oops');
      await tester.pump();
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      expect(repo.get(t.id)!.tags, ['Bug']);
      expect(text('Labels in Work'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget, reason: 'form open');

      // Saving applies it.
      await tester.tap(find.byTooltip('Edit labels'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Bug'), 'Defect');
      await tester.pump();
      expect(repo.get(t.id)!.tags, ['Bug'], reason: 'not until Save');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.get(other.id)!.tags, ['Defect']);
      expect(repo.get(t.id)!.tags, ['Defect']);
      expect(
        find.descendant(
          of: find.byType(TaskEditor),
          matching: find.widgetWithText(LabelChip, 'Defect'),
        ),
        findsOneWidget,
      );
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      expect(save.onPressed, isNull, reason: 'nothing left unsaved');

      // Escape closes just the labels, over the form.
      await tester.tap(find.byTooltip('Edit labels'));
      await tester.pumpAndSettle();
      expect(text('Labels in Work'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(text('Labels in Work'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);

      // A color from the grid.
      await tester.tap(find.byTooltip('Edit labels'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Color'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Color 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(ProjectRepository(store).get(pid)!.labelColors['defect'], 2);

      // Deleting asks first (tasks use it), then takes it off them.
      await tester.tap(find.byTooltip('Edit labels'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete label'));
      await tester.pump();
      expect(repo.get(t.id)!.tags, ['Defect'], reason: 'not until Save');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(text('It will be removed from 2 tasks.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete and save'));
      await tester.pumpAndSettle();
      expect(repo.get(t.id)!.tags, isEmpty);
      expect(repo.get(other.id)!.tags, isEmpty);
      expect(
        find.descendant(
          of: find.byType(TaskEditor),
          matching: find.byType(LabelChip),
        ),
        findsNothing,
        reason: 'gone from form',
      );

      // Nor offered again in the label field.
      await tester.tap(
        find.widgetWithText(TextField, 'Add label, press Enter'),
      );
      await tester.pumpAndSettle();
      expect(text('Defect'), findsNothing);
    });

    testWidgets('the label list shows labels not on the task, on focus and '
        'after adding one', (tester) async {
      // Labels used on the project's other tasks.
      repo.create(originId: pid, title: 'Other', tags: ['Beta', 'Gamma']);
      final t = repo.create(originId: pid, title: 'T', tags: ['Alpha']);
      await pumpPage(tester);
      await tester.tap(text('T'));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, 'Add label, press Enter');
      // The Other card on the board shows Beta and Gamma too.
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(text('Beta'), findsNWidgets(2));
      expect(text('Gamma'), findsNWidgets(2));

      await tester.tap(text('Beta').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TaskEditor),
          matching: find.widgetWithText(LabelChip, 'Beta'),
        ),
        findsOneWidget,
        reason: 'now a chip on the task',
      );
      expect(text('Gamma'), findsNWidgets(2), reason: 'list still open');

      await tester.enterText(field, 'Delta');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TaskEditor),
          matching: find.widgetWithText(LabelChip, 'Delta'),
        ),
        findsOneWidget,
      );

      // A new label: pick a color under Create, then Enter.
      await tester.enterText(field, 'Epsilon');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Label color 4'));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      store.put('projects', pid, project.toJson());
      await tester.tap(text('Save changes'));
      await tester.pumpAndSettle();
      expect(ProjectRepository(store).get(pid)!.labelColors['epsilon'], 3);
      expect(text('Gamma'), findsNWidgets(2), reason: 'still open after Enter');
      expect(repo.get(t.id)!.tags, ['Alpha', 'Beta', 'Delta', 'Epsilon']);
    });
  });
}
