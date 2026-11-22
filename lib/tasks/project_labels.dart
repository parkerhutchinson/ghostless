import '../projects/project_repository.dart';
import 'label_colors.dart';
import 'task_repository.dart';

/// What a label edit did, so an open task form can follow along: labels
/// renamed (old name lowercased → new name) and deleted (lowercased).
final class LabelChanges {
  final Map<String, String> renamed = {};
  final Set<String> deleted = {};

  bool get isEmpty => renamed.isEmpty && deleted.isEmpty;

  /// [labels] with the renames and deletions applied (no duplicates,
  /// ignoring case).
  List<String> applyTo(List<String> labels) {
    final seen = <String>{};
    return [
      for (final l in labels)
        if (renamed[l.toLowerCase()] ?? l case final name
            when !deleted.contains(l.toLowerCase()) &&
                !deleted.contains(name.toLowerCase()) &&
                seen.add(name.toLowerCase()))
          name,
    ];
  }
}

/// A project's labels, edited everywhere at once: the project's list (and
/// colors) and every task in the project that has the label.
class ProjectLabels {
  ProjectLabels(this.projects, this.tasks, this.projectId);

  final ProjectRepository projects;
  final TaskRepository tasks;
  final String projectId;

  /// The project's labels (kept on it, or on its tasks), sorted, one per
  /// spelling ignoring case.
  List<String> all() {
    final byKey = <String, String>{};
    for (final l in projects.get(projectId)?.labels ?? const <String>[]) {
      byKey.putIfAbsent(l.toLowerCase(), () => l);
    }
    for (final t in tasks.inProject(projectId)) {
      for (final l in t.tags) {
        byKey.putIfAbsent(l.toLowerCase(), () => l);
      }
    }
    return byKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// [label]'s color on this project: as picked, or its default (a label
  /// palette index).
  int colorOf(String label) =>
      projects.get(projectId)?.labelColors[label.toLowerCase()] ??
      defaultLabelColor(label);

  /// How many of the project's tasks have [label].
  int usage(String label) => tasks
      .inProject(projectId)
      .where((t) => t.tags.any((l) => _same(l, label)))
      .length;

  /// Sets [label]'s color (a label palette index).
  void setColor(String label, int color) {
    final project = projects.get(projectId);
    if (project == null) return;
    projects.save(
      project.copyWith(
        labelColors: {...project.labelColors, label.toLowerCase(): color},
      ),
    );
  }

  /// Renames [from] to [to] on the project and its tasks. Renaming onto
  /// another existing label merges the two (keeping that one's color).
  /// Returns false when [to] is blank (nothing changes).
  bool rename(String from, String to, LabelChanges changes) {
    final name = to.trim();
    if (name.isEmpty) return false;
    if (name == from) return true;
    final fromKey = from.toLowerCase(), toKey = name.toLowerCase();
    final project = projects.get(projectId);
    if (project != null) {
      final colors = {...project.labelColors};
      final color = colors.remove(fromKey);
      if (color != null) colors.putIfAbsent(toKey, () => color);
      projects.save(
        project.copyWith(
          labels: _dedupe([
            for (final l in project.labels) _same(l, from) ? name : l,
          ]),
          labelColors: colors,
        ),
      );
    }
    for (final t in tasks.inProject(projectId)) {
      if (!t.tags.any((l) => _same(l, from))) continue;
      tasks.save(
        t.copyWith(
          tags: _dedupe([for (final l in t.tags) _same(l, from) ? name : l]),
        ),
      );
    }
    changes.renamed[fromKey] = name;
    changes.deleted.remove(toKey);
    // Earlier renames onto [from] now end at [name].
    changes.renamed.updateAll((_, v) => _same(v, from) ? name : v);
    return true;
  }

  /// Deletes [label] from the project and takes it off its tasks.
  void delete(String label, LabelChanges changes) {
    final project = projects.get(projectId);
    if (project != null) {
      projects.save(
        project.copyWith(
          labels: [
            for (final l in project.labels)
              if (!_same(l, label)) l,
          ],
          labelColors: {...project.labelColors}..remove(label.toLowerCase()),
        ),
      );
    }
    for (final t in tasks.inProject(projectId)) {
      if (!t.tags.any((l) => _same(l, label))) continue;
      tasks.save(
        t.copyWith(
          tags: [
            for (final l in t.tags)
              if (!_same(l, label)) l,
          ],
        ),
      );
    }
    changes.deleted.add(label.toLowerCase());
  }

  static bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  static List<String> _dedupe(List<String> labels) {
    final seen = <String>{};
    return [
      for (final l in labels)
        if (seen.add(l.toLowerCase())) l,
    ];
  }
}
