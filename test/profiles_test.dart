import 'dart:io';

import 'package:codename/app_theme.dart' show defaultAccent;
import 'package:codename/profiles/profile.dart';
import 'package:codename/profiles/profile_repository.dart';
import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late ProjectRepository projects;
  late ProfileRepository profiles;
  late SettingsRepository settings;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('profiles_test');
    store = LocalStore.inMemory();
    projects = ProjectRepository(store);
    profiles = ProfileRepository(store, dir, projects);
    settings = SettingsRepository(store, dir, profiles: profiles);
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  File picked(String name) =>
      File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('names, initials and JSON round-trip', () {
    final p = Profile(
      id: 'p',
      name: 'Ada Lovelace',
      department: 'Engineering',
      jobTitle: 'Analyst',
      description: 'Wrote the first program.',
      imageFile: 'a.png',
      personalProjectId: 'x',
      theme: const {'accent': 1},
      createdAt: DateTime.utc(2026),
    );
    expect(p.fullName, 'Ada Lovelace');
    expect(p.initials, 'AL');
    final back = Profile.fromJson('p', p.toJson());
    expect(back.toJson(), p.toJson());
    final blank = Profile(id: 'b', createdAt: DateTime.utc(2026));
    expect(blank.initials, '');
    expect(blank.displayName, 'Unnamed profile');
    expect(Profile.fromJson('z', {}).name, '');
  });

  test('initials come from the first and last word of the name', () {
    Profile named(String name) =>
        Profile(id: 'p', name: name, createdAt: DateTime.utc(2026));
    expect(named('Ada').initials, 'A');
    expect(named('  ada   king lovelace ').initials, 'AL');
    expect(named('Ada Ada').initials, 'AA');
  });

  test('older profiles with a first and last name load as one name', () {
    final old = Profile.fromJson('o', {
      'firstName': 'Grace',
      'lastName': 'Hopper',
    });
    expect(old.name, 'Grace Hopper');
    expect(Profile.fromJson('o', {'firstName': 'Grace'}).name, 'Grace');
    expect(old.department, '');
    expect(old.jobTitle, '');
    expect(old.description, '');
  });

  test('the first launch makes one profile with a personal project, '
      'taking over the old theme', () {
    store.put('ui', 'settings', {'accent': 0xFF00695C});
    final me = profiles.ensureProfile();
    expect(profiles.all(), hasLength(1));
    expect(profiles.current!.id, me.id);
    final personal = projects.get(me.personalProjectId!)!;
    expect(personal.ownerId, me.id);
    expect(personal.name, ProfileRepository.personalProjectName);
    expect(settings.accent, const Color(0xFF00695C));
    // Again: nothing new.
    profiles.ensureProfile();
    expect(profiles.all(), hasLength(1));
    expect(projects.current(), hasLength(1));
  });

  test('a new profile gets its own personal project and becomes current', () {
    final me = profiles.ensureProfile();
    final other = profiles.create(name: ' Grace Hopper ');
    expect(other.name, 'Grace Hopper');
    expect(profiles.current!.id, other.id);
    expect(other.personalProjectId, isNot(me.personalProjectId));
    profiles.switchTo(me.id);
    expect(profiles.current!.id, me.id);
  });

  test('each profile sees shared projects and only its own personal one', () {
    final me = profiles.ensureProfile();
    final other = profiles.create(switchTo: false);
    final shared = projects.create('Company');
    final visible = visibleProjects(projects.current(), me.id);
    expect({for (final p in visible) p.id}, {shared.id, me.personalProjectId});
    expect(
      visibleProjects(projects.current(), other.id).map((p) => p.id),
      isNot(contains(me.personalProjectId)),
    );
  });

  test('each profile has its own theme', () async {
    final me = profiles.ensureProfile();
    settings.setAccent(const Color(0xFF7A4FD0));
    settings.setBackgroundColor(const Color(0xFF19451C));
    settings.setBackground(null);
    profiles.create(name: 'Other');
    expect(settings.accent, defaultAccent);
    expect(settings.backgroundColor, isNot(const Color(0xFF19451C)));
    expect(settings.background, isNull);
    profiles.switchTo(me.id);
    expect(settings.accent, const Color(0xFF7A4FD0));
    expect(settings.backgroundColor, const Color(0xFF19451C));
    expect(settings.background, isNull);
  });

  test('switching profiles updates the watched accent', () async {
    final me = profiles.ensureProfile();
    settings.setAccent(const Color(0xFF7A4FD0));
    final other = profiles.create(switchTo: false);
    final seen = <Color>[];
    final sub = settings.watchAccent().listen(seen.add);
    await pumpEventQueue();
    profiles.switchTo(other.id);
    await pumpEventQueue();
    profiles.switchTo(me.id);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [
      const Color(0xFF7A4FD0),
      defaultAccent,
      const Color(0xFF7A4FD0),
    ]);
  });

  test('a background image another profile uses is kept', () async {
    final me = profiles.ensureProfile();
    final image = await settings.setBackgroundImage(picked('bg.png').path);
    final file = settings.backgroundFile(image.fileName);
    // The other profile uses the same image file.
    final other = profiles.create();
    settings.setBackground(image);
    profiles.switchTo(me.id);
    // Replaced by a new upload here: kept, as the other profile's.
    await settings.setBackgroundImage(picked('new.png').path);
    expect(file.existsSync(), isTrue);
    settings.deleteUnusedBackgroundImages();
    expect(file.existsSync(), isTrue);
    profiles.switchTo(other.id);
    settings.setBackground(null);
    // Still kept: no image keeps it to pick again.
    settings.deleteUnusedBackgroundImages();
    expect(file.existsSync(), isTrue);
  });

  test('a photo is copied in, replaced and removed', () async {
    final me = profiles.ensureProfile();
    final first = (await profiles.setImage(me.id, picked('a.png').path))!;
    final firstFile = profiles.imageFile(first.imageFile!);
    expect(firstFile.existsSync(), isTrue);
    final second = (await profiles.setImage(me.id, picked('b.jpg').path))!;
    expect(firstFile.existsSync(), isFalse);
    expect(second.imageFile, endsWith('.jpg'));
    profiles.removeImage(me.id);
    expect(profiles.get(me.id)!.imageFile, isNull);
    expect(profiles.imageFile(second.imageFile!).existsSync(), isFalse);
  });
}
