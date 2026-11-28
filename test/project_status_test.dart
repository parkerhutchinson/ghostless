import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/status/status_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  final project = Project(id: 'p', name: 'Launch', createdAt: DateTime.utc(2026));

  test('a project has no status until one is picked', () {
    expect(project.status, isNull);
    expect(project.toJson()['status'], isNull);
    expect(Project.fromJson('p', project.toJson()).status, isNull);
  });

  test('each status is stored by name and read back', () {
    for (final s in ProjectStatus.values) {
      final json = project.copyWith(status: s).toJson();
      expect(json['status'], s.name);
      expect(Project.fromJson('p', json).status, s);
    }
  });

  test('copyWith keeps the status unless given, and can clear it', () {
    final atRisk = project.copyWith(status: ProjectStatus.atRisk);
    expect(atRisk.copyWith(name: 'Renamed').status, ProjectStatus.atRisk);
    expect(atRisk.copyWith(status: null).status, isNull);
  });

  test('an unknown stored status reads as none', () {
    expect(ProjectStatus.from('paused'), isNull);
    expect(ProjectStatus.from(3), isNull);
  });

  group('status updates', () {
    late ProjectRepository projects;
    late StatusUpdateRepository updates;
    setUp(() {
      final store = LocalStore.inMemory();
      projects = ProjectRepository(store)..save(project);
      updates = StatusUpdateRepository(store, projects);
    });

    test('posting sets the project status; listed newest first', () {
      updates.post(
        project: project,
        authorId: 'ana',
        status: ProjectStatus.onTrack,
        body: ' Going well. ',
        now: DateTime.utc(2026, 11, 1),
      );
      updates.post(
        project: projects.get('p')!,
        authorId: 'jo',
        status: ProjectStatus.atRisk,
        body: '',
        now: DateTime.utc(2026, 11, 2),
      );
      expect(projects.get('p')!.status, ProjectStatus.atRisk);
      final list = updates.forProject('p');
      expect([for (final u in list) u.authorId], ['jo', 'ana']);
      expect(list.last.body, 'Going well.');
      expect(updates.forProject('other'), isEmpty);
    });

    test('an update is stored and read back', () {
      final u = updates.post(
        project: project,
        authorId: 'ana',
        status: ProjectStatus.onHold,
        body: '**Paused**',
        now: DateTime.utc(2026, 11, 3),
      );
      final back = StatusUpdate.fromJson(u.id, u.toJson())!;
      expect(
        (back.projectId, back.authorId, back.status, back.body, back.createdAt),
        ('p', 'ana', ProjectStatus.onHold, '**Paused**', DateTime.utc(2026, 11, 3)),
      );
      expect(StatusUpdate.fromJson('x', {'projectId': 'p', 'authorId': 'a'}), isNull);
    });
  });
}
