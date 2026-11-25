import 'package:codename/projects/project_views.dart';
import 'package:codename/tasks/tasks_page.dart' show TaskView;
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  test('each project keeps its own view; the board by default', () async {
    final store = LocalStore.inMemory();
    final views = ProjectViews(store);
    expect(views.of('general'), TaskView.board);

    views.set('general', TaskView.list);
    views.set('testing', TaskView.dashboard);
    expect(views.of('general'), TaskView.list);
    expect(views.of('testing'), TaskView.dashboard);
    expect(views.of('other'), TaskView.board);

    // Back to the board, and kept across a restart (a new reader).
    views.set('testing', TaskView.board);
    expect(ProjectViews(store).of('testing'), TaskView.board);
    expect(ProjectViews(store).of('general'), TaskView.list);
    await store.close();
  });

  test('an unknown stored name falls back to the board', () async {
    final store = LocalStore.inMemory()..put('ui', 'views', {'p': 'gallery'});
    expect(ProjectViews(store).of('p'), TaskView.board);
    await store.close();
  });
}
