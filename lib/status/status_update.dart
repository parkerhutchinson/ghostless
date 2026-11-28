import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import '../projects/project.dart';
import '../projects/project_repository.dart';

/// A status update on a shared project (collection `status_updates`,
/// synced): who posted it, when, the status it set, and what they wrote.
/// Kept apart from the project, like comments, so people posting at once
/// don't overwrite each other. The latest one's status is the project's
/// ([Project.status]).
final class StatusUpdate {
  const StatusUpdate({
    required this.id,
    required this.projectId,
    required this.authorId,
    required this.status,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String projectId;

  /// The profile that posted it.
  final String authorId;

  final ProjectStatus status;

  /// What they wrote, in Markdown (the editor's subset); may be empty.
  final String body;

  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'authorId': authorId,
    'status': status.name,
    'body': body,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Null for a record this version can't read (no project, author or
  /// known status).
  static StatusUpdate? fromJson(String id, Map<String, Object?> json) {
    final project = json['projectId'], author = json['authorId'];
    final status = ProjectStatus.from(json['status']);
    if (project is! String || author is! String || status == null) {
      return null;
    }
    return StatusUpdate(
      id: id,
      projectId: project,
      authorId: author,
      status: status,
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// Reads and posts projects' status updates in the local store (synced).
class StatusUpdateRepository {
  StatusUpdateRepository(this._store, this._projects);

  static const collection = 'status_updates';
  final LocalStore _store;
  final ProjectRepository _projects;

  /// [projectId]'s updates, newest first. Updates live.
  Stream<List<StatusUpdate>> watch(String projectId) =>
      _store.watch(collection).map((all) => _of(all, projectId));

  /// [projectId]'s updates, newest first.
  List<StatusUpdate> forProject(String projectId) =>
      _of(_store.all(collection), projectId);

  /// Posts an update by [authorId] on [project], and sets the project's
  /// status to [status]. Returns it.
  StatusUpdate post({
    required Project project,
    required String authorId,
    required ProjectStatus status,
    required String body,
    DateTime? now,
  }) {
    final update = StatusUpdate(
      id: newId(),
      projectId: project.id,
      authorId: authorId,
      status: status,
      body: body.trim(),
      createdAt: now ?? DateTime.now().toUtc(),
    );
    _store.put(collection, update.id, update.toJson());
    // As stored now (it may have changed since [project] was read).
    final current = _projects.get(project.id) ?? project;
    if (current.status != status) {
      _projects.save(current.copyWith(status: status));
    }
    return update;
  }

  static List<StatusUpdate> _of(
    Map<String, Map<String, Object?>> records,
    String projectId,
  ) => [
    for (final MapEntry(:key, :value) in records.entries)
      if (value['projectId'] == projectId) ?StatusUpdate.fromJson(key, value),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
