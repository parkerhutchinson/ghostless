import 'dart:io';

import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import '../data/merge_streams.dart';
import '../projects/project_repository.dart';
import 'profile.dart';

/// Reads and writes profiles (collection `profiles`, synced), and which
/// one is using the app on this Mac (the `ui` collection, not synced).
class ProfileRepository {
  ProfileRepository(
    this._store,
    Directory appDirectory,
    this._projects, {
    this.onFileDeleted,
  }) : imagesDir = Directory('${appDirectory.path}/profile_images');

  /// A photo was deleted (by file name): online storage deletes its copy
  /// too.
  final void Function(String name)? onFileDeleted;

  static const collection = 'profiles';
  static const _ui = 'ui', _sessionKey = 'session';

  /// Where settings were kept before profiles: moved into the first
  /// profile's theme (see [ensureProfile]).
  static const _legacySettingsKey = 'settings';

  /// Name of each new profile's personal project.
  static const personalProjectName = 'Personal';

  final LocalStore _store;
  final ProjectRepository _projects;

  /// Profile photos are copied here.
  final Directory imagesDir;

  /// Every profile, oldest first.
  List<Profile> all() => _sorted(_store.all(collection));

  Stream<List<Profile>> watch() => _store.watch(collection).map(_sorted);

  Profile? get(String id) => switch (_store.get(collection, id)) {
    final json? => Profile.fromJson(id, json),
    null => null,
  };

  /// The profile using the app on this Mac: the one last switched to, or
  /// the oldest if that one's gone. Null only before [ensureProfile].
  Profile? get current {
    final id = _store.get(_ui, _sessionKey)?['profileId'] as String?;
    return (id == null ? null : get(id)) ?? all().firstOrNull;
  }

  /// [current], now and whenever it (or which one it is) changes.
  Stream<Profile?> watchCurrent() =>
      mergeStreams([_store.watch(collection), _store.watch(_ui)])
          .map((_) => current)
          .distinct(_same);

  /// Makes sure there's a current profile with a personal project. The
  /// first launch with profiles creates an unnamed one, which takes over
  /// the theme picked before profiles existed. Returns it.
  Profile ensureProfile() {
    var profile =
        current ?? create(theme: {...?_store.get(_ui, _legacySettingsKey)});
    if (profile.personalProjectId == null ||
        _projects.get(profile.personalProjectId!) == null) {
      profile = _withPersonalProject(profile);
    }
    return profile;
  }

  /// Creates a profile with its own personal project, and switches to it
  /// unless [switchTo] is false.
  Profile create({
    String name = '',
    Map<String, Object?> theme = const {},
    bool switchTo = true,
  }) {
    final profile = _withPersonalProject(
      Profile(
        id: newId(),
        name: name.trim(),
        theme: theme,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (switchTo) this.switchTo(profile.id);
    return profile;
  }

  /// Makes [id] the profile using the app on this Mac.
  void switchTo(String id) => _store.put(_ui, _sessionKey, {'profileId': id});

  void save(Profile profile) =>
      _store.put(collection, profile.id, profile.toJson());

  /// Saves [theme] as the current profile's theme.
  void saveTheme(Map<String, Object?> theme) {
    final profile = current;
    if (profile != null) save(profile.copyWith(theme: theme));
  }

  /// Stars or unstars [projectId] for the current profile (see
  /// [Profile.favoriteProjects]): starring adds it at the end.
  void setFavorite(String projectId, bool favorite) {
    final profile = current;
    if (profile == null || profile.isFavorite(projectId) == favorite) return;
    save(
      profile.copyWith(
        favoriteProjects: favorite
            ? [...profile.favoriteProjects, projectId]
            : [
                for (final id in profile.favoriteProjects)
                  if (id != projectId) id,
              ],
      ),
    );
  }

  /// Copies a picked image in as [profileId]'s photo, replacing (and
  /// deleting) any previous one.
  Future<Profile?> setImage(String profileId, String sourcePath) async {
    final profile = get(profileId);
    if (profile == null) return null;
    await imagesDir.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot == -1 ? '' : sourcePath.substring(dot).toLowerCase();
    final name = '${newId()}$ext';
    await File(sourcePath).copy(imageFile(name).path);
    final updated = profile.copyWith(imageFile: name);
    save(updated);
    if (profile.imageFile case final old?) _deleteImage(old);
    return updated;
  }

  /// Removes [profileId]'s photo (and its file).
  void removeImage(String profileId) {
    final profile = get(profileId);
    if (profile?.imageFile case final old?) {
      save(profile!.copyWith(imageFile: null));
      _deleteImage(old);
    }
  }

  File imageFile(String name) => File('${imagesDir.path}/$name');

  Profile _withPersonalProject(Profile profile) {
    final project = _projects.create(personalProjectName, ownerId: profile.id);
    final updated = profile.copyWith(personalProjectId: project.id);
    save(updated);
    return updated;
  }

  void _deleteImage(String name) {
    final file = imageFile(name);
    if (file.existsSync()) file.deleteSync();
    onFileDeleted?.call(name);
  }

  static bool _same(Profile? a, Profile? b) =>
      a?.id == b?.id && (a == null || _jsonEquals(a.toJson(), b!.toJson()));

  static bool _jsonEquals(Object? a, Object? b) => switch ((a, b)) {
    (final Map a, final Map b) =>
      a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _jsonEquals(a[k], b[k])),
    (final List a, final List b) =>
      a.length == b.length &&
          [for (var i = 0; i < a.length; i++) i]
              .every((i) => _jsonEquals(a[i], b[i])),
    _ => a == b,
  };

  static List<Profile> _sorted(Map<String, Map<String, Object?>> records) => [
    for (final MapEntry(:key, :value) in records.entries)
      Profile.fromJson(key, value),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
