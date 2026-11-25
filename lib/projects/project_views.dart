import 'package:sync_engine/sync_engine.dart';

import '../tasks/tasks_page.dart' show TaskView;

/// Which view (board, list or dashboard) each project was last left in, so
/// it opens that way again. Kept on this Mac only (`ui/views`, not synced):
/// it's how this person likes to look at it, not part of the project.
class ProjectViews {
  ProjectViews(this._store);

  static const _collection = 'ui', _key = 'views';
  final LocalStore _store;

  /// [projectId]'s view: the board until another is picked.
  TaskView of(String projectId) {
    final name = _store.get(_collection, _key)?[projectId];
    return TaskView.values.where((v) => v.name == name).firstOrNull ??
        TaskView.board;
  }

  void set(String projectId, TaskView view) {
    final views = {...?_store.get(_collection, _key)};
    // The board is the default: not stored.
    if (view == TaskView.board) {
      views.remove(projectId);
    } else {
      views[projectId] = view.name;
    }
    _store.put(_collection, _key, views);
  }
}
