import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import 'project.dart';
import 'project_logo.dart';
import '../tasks/task.dart' show TaskColumn;

/// Reads and writes projects in the local store. Saves locally right away;
/// syncing happens in the background.
class ProjectRepository {
  ProjectRepository(this._store);

  static const collection = 'projects';
  final LocalStore _store;

  /// All projects in sidebar order. Updates live.
  Stream<List<Project>> watch() => _store.watch(collection).map(_sorted);

  List<Project> current() => _sorted(_store.all(collection));

  Project? get(String id) => switch (_store.get(collection, id)) {
    final json? => Project.fromJson(id, json),
    null => null,
  };

  /// Creates a project at the bottom of the sidebar. Without [colorIndex],
  /// picks the next color in turn. With [ownerId], it's that profile's
  /// personal project.
  Project create(
    String name, {
    int? colorIndex,
    String? ownerId,
    ProjectLogo? logo,
    String description = '',
  }) {
    final all = current();
    final project = Project(
      id: newId(),
      name: name,
      colorIndex: colorIndex ?? all.length % projectHueCount,
      order: all.isEmpty ? 0 : all.last.order + 1,
      ownerId: ownerId,
      logo: logo,
      description: description,
      createdAt: DateTime.now().toUtc(),
    );
    save(project);
    return project;
  }

  void save(Project project) =>
      _store.put(collection, project.id, project.toJson());

  /// Renames [columnId] on [projectId]'s board. A blank name is ignored.
  void renameColumn(String projectId, String columnId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _editColumns(projectId, (columns) {
      final i = columns.indexWhere((c) => c.id == columnId);
      if (i != -1) columns[i] = TaskColumn(columnId, trimmed);
    });
  }

  /// Adds a column named [name] at the right end of [projectId]'s board.
  /// Returns it, or null if there's no such project.
  TaskColumn? addColumn(String projectId, String name) {
    final column = TaskColumn(
      newId(),
      name.trim().isEmpty ? 'New column' : name.trim(),
    );
    return _editColumns(projectId, (columns) => columns.add(column))
        ? column
        : null;
  }

  /// Removes [columnId] from [projectId]'s board; its tasks then show in
  /// the first column (move them first with
  /// [TaskRepository.moveColumnTasks] to choose where). A board keeps at
  /// least one column: returns false if this is the last one (or missing).
  bool removeColumn(String projectId, String columnId) {
    final project = get(projectId);
    if (project == null || project.columns.length < 2) return false;
    if (!project.columns.any((c) => c.id == columnId)) return false;
    return _editColumns(
      projectId,
      (columns) => columns.removeWhere((c) => c.id == columnId),
    );
  }

  /// Moves [columnId] to position [index] (counted without it) on
  /// [projectId]'s board.
  void moveColumn(String projectId, String columnId, int index) {
    _editColumns(projectId, (columns) {
      final i = columns.indexWhere((c) => c.id == columnId);
      if (i == -1) return;
      final column = columns.removeAt(i);
      columns.insert(index.clamp(0, columns.length), column);
    });
  }

  /// Applies [change] to a copy of [projectId]'s columns and saves it.
  bool _editColumns(String projectId, void Function(List<TaskColumn>) change) {
    final project = get(projectId);
    if (project == null) return false;
    final columns = [...project.columns];
    change(columns);
    if (columns.isEmpty) return false;
    save(project.copyWith(columns: columns));
    return true;
  }

  /// Deletes the project record only; move its tasks first
  /// (see [TaskRepository.releaseProject]).
  void delete(String id) => _store.delete(collection, id);

  static List<Project> _sorted(Map<String, Map<String, Object?>> records) =>
      [
        for (final MapEntry(:key, :value) in records.entries)
          Project.fromJson(key, value),
      ]..sort(
        (a, b) => a.order != b.order
            ? a.order.compareTo(b.order)
            : a.createdAt.compareTo(b.createdAt),
      );

  /// Keeps [labels] on [projectId] for the task form to suggest, adding
  /// only ones it doesn't have yet (ignoring case). [colors] (palette
  /// index by label, lowercased) are the colors picked for new ones; a
  /// label's first color sticks.
  void addLabels(
    String projectId,
    Iterable<String> labels, {
    Map<String, int> colors = const {},
  }) {
    final project = get(projectId);
    if (project == null) return;
    final known = {for (final l in project.labels) l.toLowerCase()};
    final added = [
      for (final l in labels.map((l) => l.trim()))
        if (l.isNotEmpty && known.add(l.toLowerCase())) l,
    ];
    final newColors = {
      for (final l in labels.map((l) => l.trim().toLowerCase()))
        if (colors[l] case final c?)
          if (!project.labelColors.containsKey(l)) l: c,
    };
    if (added.isEmpty && newColors.isEmpty) return;
    save(
      project.copyWith(
        labels: [...project.labels, ...added],
        labelColors: {...project.labelColors, ...newColors},
      ),
    );
  }
}
