import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

import '../data/ids.dart';
import '../app_theme.dart' show defaultAccent;
import '../profiles/profile.dart';
import '../profiles/profile_repository.dart';
import 'background.dart';

/// The theme settings (accent, background). With [profiles], they belong
/// to the current profile (its [Profile.theme]), so each person has their
/// own and switching profiles switches the theme. Without it (tests), they
/// live in the local store on this Mac only.
class SettingsRepository {
  SettingsRepository(
    this._store,
    Directory appDirectory, {
    ProfileRepository? profiles,
  }) : _profiles = profiles, // ignore: prefer_initializing_formals
       backgroundsDir = Directory('${appDirectory.path}/backgrounds');

  static const _collection = 'ui', _key = 'settings';

  final LocalStore _store;
  final ProfileRepository? _profiles;

  /// Background images the user picked are copied here.
  final Directory backgroundsDir;

  /// The image over the background color; null for none. Until one is
  /// picked (or "No image"), it's the image that ships with the app.
  Background? get background =>
      Background.fromJson(_settings['background'] as Map<String, Object?>?);

  /// The image the user last uploaded (its file name), kept while another
  /// choice (No image) is showing so it can be picked again; null if none.
  /// Older settings only had it as the background.
  String? get uploadedImage => switch (_settings['backgroundUpload']) {
    final String name when name.isNotEmpty => name,
    _ => switch (background) {
      ImageBackground(:final fileName) => fileName,
      null => null,
    },
  };

  /// The background image, now and whenever it changes.
  Stream<Background?> watchBackground() =>
      _changes.map((_) => background).distinct();

  /// Switches the background image (null for none), leaving the colors
  /// alone. The uploaded image is kept either way ([uploadedImage]).
  void setBackground(Background? value) =>
      _writeBackground({'background': value?.toJson()});

  /// The background color: what the app's surfaces, borders and text are
  /// worked out from (see AppColors), with or without an image over it.
  Color get backgroundColor => backgroundColorFromJson(_settings);

  /// The background color, now and whenever it changes.
  Stream<Color> watchBackgroundColor() =>
      _changes.map((_) => backgroundColor).distinct();

  /// Switches the background color, leaving the image alone. Also used
  /// for live previews in the color picker.
  void setBackgroundColor(Color value) =>
      _writeBackground({'backgroundColor': value.toARGB32()});

  /// Writes [changes], keeping the color and image as they are otherwise
  /// (older settings stored the color under `background`).
  void _writeBackground(Map<String, Object?> changes) => _write({
    ..._settings,
    'backgroundColor': backgroundColor.toARGB32(),
    'background': background?.toJson(),
    'backgroundUpload': uploadedImage,
    ...changes,
  });

  /// Deletes picked images that aren't the background any more.
  void deleteUnusedBackgroundImages() {
    if (!backgroundsDir.existsSync()) return;
    final keep = _imagesInUse();
    for (final file in backgroundsDir.listSync().whereType<File>()) {
      if (!keep.contains(file.uri.pathSegments.last)) file.deleteSync();
    }
  }

  /// Copies a picked image into the app and makes it the background (and
  /// the [uploadedImage]). The one uploaded before is deleted, unless
  /// another profile uses it.
  Future<ImageBackground> setBackgroundImage(String sourcePath) async {
    await backgroundsDir.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot == -1 ? '' : sourcePath.substring(dot).toLowerCase();
    final name = '${newId()}$ext';
    await File(sourcePath).copy(backgroundFile(name).path);
    final previous = uploadedImage;
    final value = ImageBackground(name);
    _writeBackground({'background': value.toJson(), 'backgroundUpload': name});
    if (previous != null &&
        previous != name &&
        !_imagesInUse().contains(previous)) {
      _deleteFile(previous);
    }
    return value;
  }

  /// The accent color (buttons, the selected project, highlights).
  Color get accent => switch (_settings['accent']) {
    final int argb => Color(argb),
    _ => defaultAccent,
  };

  /// The accent, now and whenever it changes.
  Stream<Color> watchAccent() => _changes.map((_) => accent).distinct();

  void setAccent(Color value) =>
      _write({..._settings, 'accent': value.toARGB32()});

  File backgroundFile(String name) => File('${backgroundsDir.path}/$name');

  Map<String, Object?> get _settings => switch (_profiles?.current) {
    final profile? => profile.theme,
    null => _store.get(_collection, _key) ?? {},
  };

  void _write(Map<String, Object?> settings) => switch (_profiles) {
    final profiles? => profiles.saveTheme(settings),
    null => _store.put(_collection, _key, settings),
  };

  /// Fires when the settings may have changed (including switching
  /// profiles).
  Stream<Object?> get _changes => switch (_profiles) {
    final profiles? => profiles.watchCurrent(),
    null => _store.watch(_collection),
  };

  /// Background image files some profile (or this Mac's settings) uses:
  /// as its background, or kept as its uploaded image.
  Set<String> _imagesInUse() => {
    for (final theme in [
      if (_profiles case final profiles?)
        for (final p in profiles.all()) p.theme
      else
        _settings,
    ]) ...[
      if (Background.fromJson(theme['background'] as Map<String, Object?>?)
          case ImageBackground(:final fileName))
        fileName,
      if (theme['backgroundUpload'] case final String name) name,
    ],
  };

  void _deleteFile(String name) {
    final file = backgroundFile(name);
    if (file.existsSync()) file.deleteSync();
  }
}
