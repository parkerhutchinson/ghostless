import 'support/finders.dart';

import 'dart:io';

import 'package:codename/activity/activity_repository.dart';
import 'package:codename/profiles/profile_repository.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/projects/workspace.dart';
import 'package:codename/settings/settings_repository.dart';
import 'package:codename/tasks/task.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late TaskRepository tasks;
  late ProjectRepository projects;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('projects_test');
    store = LocalStore.inMemory();
    projects = ProjectRepository(store);
    // Wired to the projects' columns, as in the app.
    tasks = TaskRepository(
      store,
      dir,
      columnFor: (id, status) => projects.get(id)?.columnFor(status) ?? status,
    );
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  /// Titles in [status]'s column on [projectId]'s board, in order.
  List<String> titles(String projectId, [String status = 'todo']) => [
    for (final t in tasks.viewsIn(projectId).where((t) => t.status == status))
      t.title,
  ];

  group('repositories', () {
    test('projects are created in order with rotating colors', () {
      final a = projects.create('Alpha');
      final b = projects.create('Beta');
      expect(projects.current().map((p) => p.name), ['Alpha', 'Beta']);
      expect(a.colorIndex, isNot(b.colorIndex));
    });

    group('completing', () {
      test('checks a task off without moving it', () {
        final p = projects.create('P');
        final t = tasks.create(title: 'T', originId: p.id, status: 'doing');
        final before = tasks.toggleCompleted(t.id, projectId: p.id)!;
        expect(before.isCompletedIn(p.id), isFalse, reason: 'as it was');
        expect(tasks.get(t.id)!.isCompletedIn(p.id), isTrue);
        expect(titles(p.id, 'doing'), ['T'], reason: 'same column');
        tasks.toggleCompleted(t.id, projectId: p.id);
        expect(tasks.get(t.id)!.isCompletedIn(p.id), isFalse);
      });

      test('moving a task leaves it checked off', () {
        final p = projects.create('P');
        final t = tasks.create(title: 'T', originId: p.id);
        tasks.toggleCompleted(t.id, projectId: p.id);
        tasks.move(t.id, 'done', 0, projectId: p.id);
        tasks.move(t.id, 'todo', 0, projectId: p.id);
        expect(tasks.get(t.id)!.isCompletedIn(p.id), isTrue);
      });

      test('is separate on each board', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final t = tasks.create(title: 'T', originId: a.id, multiHomes: [b.id]);
        tasks.toggleCompleted(t.id, projectId: b.id);
        expect(tasks.get(t.id)!.isCompletedIn(b.id), isTrue);
        expect(tasks.get(t.id)!.isCompletedIn(a.id), isFalse);
      });

      test('leaving a project forgets it was checked off there', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final t = tasks.create(title: 'T', originId: a.id, multiHomes: [b.id]);
        tasks.toggleCompleted(t.id, projectId: b.id);
        tasks.removeFromProject(t.id, b.id);
        tasks.addToProject(t.id, b.id);
        expect(tasks.get(t.id)!.isCompletedIn(b.id), isFalse);
      });

      test('is saved and loaded', () {
        final p = projects.create('P');
        final t = tasks.create(title: 'T', originId: p.id);
        tasks.toggleCompleted(t.id, projectId: p.id);
        expect(store.get('tasks', t.id)!['completedIn'], [p.id]);
      });

      test('tasks saved in Done before completing was separate count as '
          'checked off there', () {
        final a = projects.create('A');
        final b = projects.create('B');
        store.put('tasks', 'old', {
          'title': 'Old',
          'status': 'done',
          'originId': a.id,
          'projectIds': [a.id, b.id],
          'placements': {
            b.id: {'status': 'todo', 'order': 0},
          },
        });
        final old = tasks.get('old')!;
        expect(old.isCompletedIn(a.id), isTrue);
        expect(old.isCompletedIn(b.id), isFalse);
        expect(old.status, 'done', reason: 'stays in its column');
      });

      test('a checked-off task is not overdue', () {
        final p = projects.create('P');
        final t = tasks.create(
          title: 'T',
          originId: p.id,
          dueDate: DateTime(2020),
        );
        expect(tasks.get(t.id)!.isOverdueIn(p.id, DateTime(2026)), isTrue);
        tasks.toggleCompleted(t.id, projectId: p.id);
        expect(tasks.get(t.id)!.isOverdueIn(p.id, DateTime(2026)), isFalse);
      });
    });

    group('columns', () {
      List<String> names(String projectId) => [
        for (final c in projects.get(projectId)!.columns) c.title,
      ];

      test('a project starts with To do, In progress and Done', () {
        final p = projects.create('P');
        expect(names(p.id), ['To do', 'In progress', 'Done']);
        expect(p.columns.map((c) => c.id), ['todo', 'doing', 'done']);
      });

      test('can be renamed per project; blank names are ignored', () {
        final p = projects.create('P');
        final q = projects.create('Q');
        projects.renameColumn(p.id, 'doing', '  Review  ');
        projects.renameColumn(p.id, 'todo', '   ');
        expect(names(p.id), ['To do', 'Review', 'Done']);
        expect(names(q.id), ['To do', 'In progress', 'Done']);
      });

      test('can be added at the end, with a unique id', () {
        final p = projects.create('P');
        final added = projects.addColumn(p.id, 'Blocked')!;
        expect(names(p.id), ['To do', 'In progress', 'Done', 'Blocked']);
        expect(defaultColumns.map((c) => c.id), isNot(contains(added.id)));
        expect(projects.addColumn(p.id, '  ')!.title, 'New column');
        expect(projects.addColumn('missing', 'X'), isNull);
      });

      test('can be moved', () {
        final p = projects.create('P');
        projects.moveColumn(p.id, 'done', 0);
        expect(names(p.id), ['Done', 'To do', 'In progress']);
        projects.moveColumn(p.id, 'done', 99); // clamps to the end
        expect(names(p.id), ['To do', 'In progress', 'Done']);
      });

      test('can be removed, but never the last one', () {
        final p = projects.create('P');
        expect(projects.removeColumn(p.id, 'doing'), isTrue);
        expect(projects.removeColumn(p.id, 'todo'), isTrue);
        expect(names(p.id), ['Done']);
        expect(projects.removeColumn(p.id, 'done'), isFalse);
        expect(projects.removeColumn(p.id, 'missing'), isFalse);
        expect(names(p.id), ['Done']);
      });

      test('are saved and loaded in order', () {
        final p = projects.create('P');
        projects.addColumn(p.id, 'Blocked');
        projects.moveColumn(p.id, 'done', 0);
        expect(
          ProjectRepository(store).get(p.id)!.columns,
          projects.get(p.id)!.columns,
        );
      });

      test('older projects keep the names they gave the defaults', () {
        store.put('projects', 'old', {
          'name': 'Old',
          'columnNames': {'doing': 'Review', 'done': ''},
        });
        expect(names('old'), ['To do', 'Review', 'Done']);
      });

      test('malformed or empty stored columns fall back sensibly', () {
        store.put('projects', 'odd', {
          'name': 'Odd',
          'columns': [
            {'id': 'a', 'name': 'A'},
            {'id': 'a', 'name': 'Duplicate'},
            {'id': '', 'name': 'No id'},
            {'id': 'b', 'name': '  '},
            'junk',
          ],
        });
        expect(names('odd'), ['A']);
        store.put('projects', 'empty', {'name': 'E', 'columns': []});
        expect(names('empty'), ['To do', 'In progress', 'Done']);
      });

      test('a status the board has no column for shows in its first one', () {
        final p = projects.create('P');
        expect(p.columnFor('doing'), 'doing');
        expect(p.columnFor('deleted-column'), 'todo');
        expect(p.columnFor(''), 'todo');
      });

      test('deleting a column: its tasks move to another, others stay', () {
        final p = projects.create('P');
        final q = projects.create('Q');
        final repo = TaskRepository(
          store,
          dir,
          columnFor: (id, s) => projects.get(id)?.columnFor(s) ?? s,
        );
        repo.create(title: 'Already', originId: p.id, status: 'todo');
        final x = repo.create(
          title: 'X',
          originId: p.id,
          status: 'doing',
          multiHomes: [q.id],
        );
        repo.move(x.id, 'doing', 0, projectId: q.id);

        final before = repo.moveColumnTasks(p.id, 'doing', 'todo');
        projects.removeColumn(p.id, 'doing');
        expect(before.single.status, 'doing', reason: 'as it was, for undo');
        expect(
          [for (final t in repo.viewsIn(p.id)) '${t.title}:${t.status}'],
          ['Already:todo', 'X:todo'],
        );
        expect(repo.get(x.id)!.placementIn(q.id).status, 'doing');
      });
    });

    test('tasks are created in a project and ordered within it', () {
      final w = projects.create('Work');
      final h = projects.create('Home');
      tasks.create(title: 'H1', originId: h.id);
      tasks.create(title: 'W1', originId: w.id);
      tasks.create(title: 'W2', originId: w.id);
      expect(titles(w.id), ['W1', 'W2']);
      expect(titles(h.id), ['H1']);
    });

    test('a task can be multi-homed and shows in each project', () {
      final a = projects.create('A');
      final b = projects.create('B');
      final t = tasks.create(
        title: 'Shared',
        originId: a.id,
        multiHomes: [b.id],
      );
      expect(t.originId, a.id);
      expect(t.multiHomes, [b.id]);
      expect(titles(a.id), ['Shared']);
      expect(titles(b.id), ['Shared']);
      expect(tasks.current(), hasLength(1), reason: 'one task, not a copy');

      tasks.move(t.id, 'done', 0, projectId: a.id);
      expect(titles(a.id, 'done'), ['Shared']);
      expect(titles(b.id), ['Shared'], reason: 'boards are separate');
    });

    group('each project has its own board', () {
      test('moving it in a multi-home leaves the origin alone, and back', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final t = tasks.create(title: 'T', originId: a.id, multiHomes: [b.id]);

        tasks.move(t.id, 'done', 0, projectId: b.id);
        expect(titles(b.id, 'done'), ['T']);
        expect(titles(a.id), ['T'], reason: 'origin unchanged');
        expect(tasks.get(t.id)!.placementIn(b.id).status == 'done', isTrue);
        expect(tasks.get(t.id)!.placementIn(a.id).status == 'done', isFalse);

        tasks.move(t.id, 'done', 0, projectId: a.id);
        expect(titles(a.id, 'done'), ['T']);
        expect(titles(b.id, 'done'), ['T']);
        tasks.move(
          t.id,
          'todo',
          0,
          projectId: b.id,
        ); // back to To do, in B only
        expect(titles(b.id), ['T']);
        expect(titles(a.id, 'done'), ['T']);
      });

      test('moving and reordering on one board leaves the other alone', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final x = tasks.create(title: 'X', originId: a.id, multiHomes: [b.id]);
        tasks.create(title: 'Y', originId: a.id, multiHomes: [b.id]);

        tasks.move(x.id, 'todo', 1, projectId: b.id); // after Y, in B
        expect(titles(b.id), ['Y', 'X']);
        expect(titles(a.id), ['X', 'Y'], reason: 'A keeps its order');

        tasks.move(x.id, 'doing', 0, projectId: b.id);
        expect(titles(b.id, 'doing'), ['X']);
        expect(titles(a.id), ['X', 'Y']);
      });

      test('a multi-home always starts at the bottom of the first column', () {
        final a = projects.create('A');
        final b = projects.create('B');
        tasks.create(title: 'Already in B', originId: b.id);
        final t = tasks.create(title: 'T', originId: a.id, status: 'doing');

        tasks.addToProject(t.id, b.id);
        expect(titles(b.id), ['Already in B', 'T'], reason: 'not "doing"');

        final u = tasks.create(title: 'U', originId: a.id, status: 'done');
        tasks.setMultiHomes(u.id, [b.id]);
        expect(titles(b.id), ['Already in B', 'T', 'U']);

        final v = tasks.create(
          title: 'V',
          originId: a.id,
          status: 'done',
          multiHomes: [b.id],
        );
        expect(tasks.get(v.id)!.placementIn(b.id).status == 'done', isFalse);
      });

      test('removing and adding back starts over in the first column', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final t = tasks.create(title: 'T', originId: a.id, multiHomes: [b.id]);
        tasks.move(t.id, 'doing', 0, projectId: b.id);
        tasks.move(t.id, 'done', 0, projectId: a.id); // origin is done

        tasks.removeFromProject(t.id, b.id);
        tasks.addToProject(t.id, b.id);
        expect(titles(b.id), ['T'], reason: 'not "doing", not "done"');
      });

      test('leaving a project forgets its place there', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final t = tasks.create(title: 'T', originId: a.id, multiHomes: [b.id]);
        tasks.move(t.id, 'done', 0, projectId: b.id);

        tasks.removeFromProject(t.id, b.id);
        expect(tasks.get(t.id)!.placements, isEmpty);
        tasks.addToProject(t.id, b.id);
        expect(titles(b.id), ['T'], reason: 'starts again from the origin');
      });

      test('places are saved and loaded; older records follow the origin', () {
        final a = projects.create('A');
        final b = projects.create('B');
        final t = tasks.create(title: 'T', originId: a.id, multiHomes: [b.id]);
        tasks.move(t.id, 'doing', 0, projectId: b.id);
        final json = store.get('tasks', t.id)!;
        expect(json['status'], 'todo');
        expect((json['placements'] as Map)[b.id], {
          'status': 'doing',
          'order': 0.0,
        });

        store.put('tasks', 'old', {
          'title': 'Old',
          'status': 'done',
          'originId': a.id,
          'projectIds': [a.id, b.id],
        });
        expect(tasks.get('old')!.placementIn(b.id).status == 'done', isTrue);
      });

      test('adopting moves the place on the new origin\'s board up', () {
        final a = projects.create('A');
        final t = tasks.create(
          title: 'T',
          originId: 'gone',
          multiHomes: [a.id],
        );
        tasks.move(t.id, 'done', 0, projectId: a.id);
        tasks.adopt(t.id, a.id);
        final adopted = tasks.get(t.id)!;
        expect(adopted.originId, a.id);
        expect(adopted.status, 'done');
        expect(adopted.placements, isEmpty);
      });
    });

    test('addToProject multi-homes a task, keeping its origin', () {
      final a = projects.create('A');
      final b = projects.create('B');
      final t = tasks.create(title: 'Task', originId: a.id);
      expect(tasks.addToProject(t.id, b.id), isTrue);
      expect(tasks.get(t.id)!.projectIds, [a.id, b.id]);
      expect(tasks.get(t.id)!.originId, a.id);
      expect(tasks.addToProject(t.id, b.id), isFalse, reason: 'already in');
    });

    test('removeFromProject removes a multi-home but never the origin', () {
      final a = projects.create('A');
      final b = projects.create('B');
      final t = tasks.create(title: 'Task', originId: a.id, multiHomes: [b.id]);
      expect(tasks.removeFromProject(t.id, a.id), isFalse, reason: 'origin');
      expect(tasks.get(t.id)!.projectIds, [a.id, b.id]);
      expect(tasks.removeFromProject(t.id, b.id), isTrue);
      expect(tasks.get(t.id)!.projectIds, [a.id]);
      expect(tasks.removeFromProject(t.id, b.id), isFalse, reason: 'not in');
    });

    test('setMultiHomes replaces the multi-homes and keeps the origin', () {
      final a = projects.create('A');
      final b = projects.create('B');
      final c = projects.create('C');
      final t = tasks.create(title: 'Task', originId: a.id, multiHomes: [b.id]);
      expect(tasks.setMultiHomes(t.id, [c.id, c.id]), isTrue);
      expect(tasks.get(t.id)!.projectIds, [a.id, c.id]);
      expect(tasks.setMultiHomes(t.id, [c.id]), isFalse, reason: 'unchanged');
      expect(tasks.setMultiHomes(t.id, [a.id]), isTrue, reason: 'origin only');
      expect(tasks.get(t.id)!.projectIds, [a.id]);
      expect(tasks.get(t.id)!.originId, a.id);
    });

    test('orphans are tasks whose origin is gone; adopt gives them one', () {
      final a = projects.create('A');
      final g = projects.create('General');
      tasks.create(title: 'Fine', originId: a.id, multiHomes: ['gone']);
      final lost = tasks.create(
        title: 'Lost',
        originId: 'gone',
        multiHomes: [a.id],
      );
      expect(tasks.orphans({a.id, g.id}).map((t) => t.id), [lost.id]);

      tasks.adopt(lost.id, g.id);
      final adopted = tasks.get(lost.id)!;
      expect(adopted.originId, g.id);
      expect(adopted.projectIds, [g.id, a.id], reason: 'keeps multi-homes');
      expect(tasks.orphans({a.id, g.id}), isEmpty);
    });

    test('reordering only considers tasks in the same project', () {
      final p = projects.create('P');
      final q = projects.create('Q');
      final x = tasks.create(title: 'X', originId: p.id);
      tasks.create(title: 'Y', originId: p.id);
      tasks.create(title: 'Elsewhere', originId: q.id);
      tasks.move(x.id, 'todo', 1); // after Y, within P
      expect(titles(p.id), ['Y', 'X']);
    });

    test('removeProject deletes tasks created in it, even multi-homed '
        'ones, keeping their images, and takes tasks multi-homed to it '
        'out of it', () async {
      final p = projects.create('Doomed');
      final other = projects.create('Other');
      final source = File('${dir.path}/a.png')..writeAsBytesSync([1]);
      final image = await tasks.addImage(source.path);
      tasks.create(title: 'one', originId: p.id, images: [image]);
      tasks.create(title: 'two', originId: p.id, multiHomes: [other.id]);
      final visitor = tasks.create(
        title: 'visitor',
        originId: other.id,
        multiHomes: [p.id],
      );

      final (:deleted, :detached) = tasks.removeProject(p.id);
      expect(deleted.map((t) => t.title), unorderedEquals(['one', 'two']));
      expect(detached.single.projectIds, [other.id, p.id], reason: 'as was');
      expect(tasks.current().single.id, visitor.id);
      expect(tasks.get(visitor.id)!.projectIds, [other.id]);
      expect(tasks.imageFile(image).existsSync(), isTrue);
    });
  });

  group('Workspace', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: Workspace(
              store: store,
              tasks: tasks,
              projects: projects,
              settings: SettingsRepository(store, dir),
              // No profile made yet: these tests are about shared projects.
              profiles: ProfileRepository(store, dir, projects),
              activity: ActivityRepository(store, actorId: () => null),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Enter in the project name creates it', (tester) async {
      await pump(tester);
      await tester.tap(text('Create your first project'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Launch');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(text('Launch'), findsNWidgets(2)); // sidebar + header
    });

    testWidgets('with no projects, offers to create the first one', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'no project yet',
      );

      await tester.tap(text('Create your first project'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Launch');
      await tester.pump();
      await tester.tap(text('Create project'));
      await tester.pumpAndSettle();

      expect(text('Launch'), findsNWidgets(2)); // sidebar + header
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Ship it',
      );
      await tester.pump();
      await tester.tap(text('Create task'));
      await tester.pumpAndSettle();

      final launch = projects.current().single;
      expect(tasks.inProject(launch.id).single.title, 'Ship it');
    });

    testWidgets('opens the remembered project, or the first one', (
      tester,
    ) async {
      projects.create('First');
      final second = projects.create('Second');
      tasks.create(title: 'Second task', originId: second.id);
      store.put('ui', 'workspace', {'projectId': second.id});
      await pump(tester);
      expect(text('Second task'), findsOneWidget);

      await tester.tap(text('First'));
      await tester.pumpAndSettle();
      expect(text('Second task'), findsNothing);
      expect(store.get('ui', 'workspace'), {
        'projectId': projects.current().first.id,
      });
    });

    testWidgets('tasks without a project are moved into "General"', (
      tester,
    ) async {
      store.put('tasks', 'legacy', {'title': 'From before projects'});
      await pump(tester);

      final general = projects.current().single;
      expect(general.name, Workspace.orphanProjectName);
      expect(tasks.get('legacy')!.projectIds, [general.id]);
      expect(text('From before projects'), findsOneWidget);
    });

    testWidgets('dragging a card onto a project in the sidebar adds it there', (
      tester,
    ) async {
      final home = projects.create('Home');
      final target = projects.create('Target');
      final t = tasks.create(title: 'Drag to project', originId: home.id);
      await pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(text('Drag to project')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(text('Target')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tasks.get(t.id)!.projectIds, [home.id, target.id]);
      expect(text('Drag to project'), findsOneWidget, reason: 'still in Home');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the Multi-home field adds and removes other projects', (
      tester,
    ) async {
      final home = projects.create('Home');
      final other = projects.create('Elsewhere');
      final t = tasks.create(title: 'Pick a project', originId: home.id);
      await pump(tester);

      await tester.tap(text('Pick a project'));
      await tester.pumpAndSettle();
      final homesBefore = text('Home').evaluate().length;
      final elsewhereBefore = text('Elsewhere').evaluate().length;
      // "Add project" opens the box: its field, the projects under it.
      await tester.tap(text('Add project'));
      await tester.pumpAndSettle();
      expect(
        text('Home'),
        findsNWidgets(homesBefore),
        reason: 'the project it was opened from is not suggested',
      );
      expect(text('Elsewhere'), findsNWidgets(elsewhereBefore + 1));
      await tester.enterText(
        find.widgetWithText(TextField, 'Find project'),
        'else',
      );
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Elsewhere'), findsOneWidget);
      expect(
        find.byTooltip('Add project'),
        findsNothing,
        reason: 'no other projects left to add: no +',
      );
      await tester.tap(text('Save changes'));
      await tester.pumpAndSettle();
      expect(tasks.get(t.id)!.projectIds, [home.id, other.id]);
      // Saving keeps the form open; the arrow closes it.
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(text('Pick a project'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Elsewhere'),
          matching: find.byIcon(Symbols.close),
        ),
      );
      await tester.pump();
      await tester.tap(text('Save changes'));
      await tester.pumpAndSettle();
      expect(tasks.get(t.id)!.projectIds, [home.id]);
    });

    testWidgets('deleting a project deletes its tasks after confirming; Undo '
        'restores both', (tester) async {
      final keep = projects.create('Keep');
      final temp = projects.create('Temp');
      final t = tasks.create(title: 'Goes with it', originId: temp.id);
      store.put('ui', 'workspace', {'projectId': temp.id});
      await pump(tester);

      await openProjectMenu(tester, 'Temp');
      await tester.pumpAndSettle();
      await tester.tap(text('Delete project'));
      await tester.pumpAndSettle();
      expect(text('Its 1 task will be deleted too.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete project'));
      await tester.pumpAndSettle();

      expect(projects.current().map((p) => p.id), [keep.id]);
      expect(tasks.get(t.id), isNull);
      expect(text('Keep'), findsNWidgets(2), reason: 'fell back to Keep');
      expect(text('"Temp" and 1 task deleted'), findsOneWidget);

      await tester.tap(text('Undo'));
      await tester.pumpAndSettle();
      expect(projects.get(temp.id), isNotNull);
      expect(tasks.get(t.id)!.projectIds, [temp.id]);
      expect(text('Goes with it'), findsOneWidget);
    });

    testWidgets('an empty project is deleted without asking', (tester) async {
      final p = projects.create('Empty');
      await pump(tester);
      await openProjectMenu(tester, 'Empty');
      await tester.pumpAndSettle();
      await tester.tap(text('Delete project'));
      await tester.pumpAndSettle();

      expect(projects.get(p.id), isNull);
      expect(text('Create your first project'), findsOneWidget);
    });

    testWidgets('rename changes the name everywhere', (tester) async {
      final p = projects.create('Old name');
      await pump(tester);

      await openProjectMenu(tester, 'Old name');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'New name');
      await tester.pump();
      await tester.tap(text('Save'));
      await tester.pumpAndSettle();

      expect(projects.get(p.id)!.name, 'New name');
      expect(text('New name'), findsNWidgets(2));
    });
  });
}

/// The pencil only shows while the pointer is over a project row: hover the
/// row named [name] in the sidebar, then open its dialog.
Future<void> openProjectMenu(WidgetTester tester, String name) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(text(name).first));
  await tester.pump();
  await tester.tap(find.byTooltip('Edit project'));
  await tester.pumpAndSettle();
}
