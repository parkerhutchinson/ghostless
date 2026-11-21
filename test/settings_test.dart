import 'dart:io';

import 'package:codename/app_theme.dart' show defaultAccent;
import 'package:codename/settings/background.dart';
import 'package:codename/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late SettingsRepository settings;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('settings_test');
    store = LocalStore.inMemory();
    settings = SettingsRepository(store, dir);
  });

  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  File picked(String name) =>
      File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('the accent starts as the default and a chosen one is saved', () {
    expect(settings.accent, defaultAccent);
    settings.setAccent(const Color(0xFF00695C));
    expect(SettingsRepository(store, dir).accent, const Color(0xFF00695C));
  });

  test('changing the accent keeps the background, and vice versa', () {
    settings.setBackground(const ColorBackground(Color(0xFF3A0F55)));
    settings.setAccent(const Color(0xFFC62828));
    expect(settings.background, const ColorBackground(Color(0xFF3A0F55)));
    settings.setBackground(const MountainsBackground());
    expect(settings.accent, const Color(0xFFC62828));
  });

  test('the background starts out about 80% black', () {
    expect(settings.background, Background.initial);
    expect(Background.initial.color, const Color(0xFF2D2D2D));
  });

  test('the mountains are saved and read back; their old name still loads', () {
    settings.setBackground(const MountainsBackground());
    expect(settings.background, const MountainsBackground());
    expect(
      Background.fromJson({'type': 'default'}),
      const MountainsBackground(),
    );
  });

  test('a chosen color is saved and read back', () {
    settings.setBackground(const ColorBackground(Color(0xFF003A33)));
    expect(
      SettingsRepository(store, dir).background,
      const ColorBackground(Color(0xFF003A33)),
    );
  });

  test('a saved color from the old brighter list loads as its darker one', () {
    expect(
      Background.fromJson({'type': 'color', 'color': 0xFF00695C}),
      const ColorBackground(Color(0xFF003A33)),
    );
    expect(
      backgroundColors,
      contains(const Color(0xFF003A33)),
      reason: 'so it shows as selected in Settings',
    );
  });

  test(
    'previewing a color keeps a picked image; cancelling restores it',
    () async {
      final image = await settings.setBackgroundImage(picked('a.png').path);
      settings.previewBackground(const ColorBackground(Color(0xFF003A33)));
      expect(settings.backgroundFile(image.fileName).existsSync(), isTrue);
      settings.previewBackground(image);
      expect(settings.background, image);
    },
  );

  test(
    'choosing a custom color after previews deletes the unused image',
    () async {
      final image = await settings.setBackgroundImage(picked('a.png').path);
      settings.previewBackground(const ColorBackground(Color(0xFF123456)));
      settings.setBackground(const ColorBackground(Color(0xFF123456)));
      settings.deleteUnusedBackgroundImages();
      expect(settings.backgroundFile(image.fileName).existsSync(), isFalse);
    },
  );

  test('cleaning up keeps the image that is the background', () async {
    final image = await settings.setBackgroundImage(picked('a.png').path);
    settings.deleteUnusedBackgroundImages();
    expect(settings.backgroundFile(image.fileName).existsSync(), isTrue);
  });

  test('any accent color is saved, not just the presets', () {
    settings.setAccent(const Color(0xFF7A4FD0));
    expect(SettingsRepository(store, dir).accent, const Color(0xFF7A4FD0));
  });

  test('a picked image is copied into the app and used', () async {
    final b = await settings.setBackgroundImage(picked('photo.JPG').path);
    expect(settings.background, b);
    expect(b.fileName, endsWith('.jpg'));
    expect(settings.backgroundFile(b.fileName).readAsBytesSync(), [1, 2, 3]);
  });

  test('replacing a picked image deletes the old copy', () async {
    final first = await settings.setBackgroundImage(picked('a.png').path);
    final second = await settings.setBackgroundImage(picked('b.png').path);
    expect(settings.backgroundFile(first.fileName).existsSync(), isFalse);
    expect(settings.backgroundFile(second.fileName).existsSync(), isTrue);

    settings.setBackground(Background.initial);
    expect(settings.backgroundFile(second.fileName).existsSync(), isFalse);
  });

  test('other settings in the same record are kept', () {
    store.put('ui', 'settings', {'other': 1});
    settings.setBackground(const ColorBackground(Color(0xFF121212)));
    expect(store.get('ui', 'settings')!['other'], 1);
  });

  test('unknown or broken values fall back to the initial background', () {
    for (final json in [
      null,
      <String, Object?>{},
      {'type': 'video'},
      {'type': 'image', 'file': ''},
      {'type': 'color', 'color': 'blue'},
    ]) {
      expect(Background.fromJson(json), Background.initial);
    }
  });

  test('watchBackground emits on change, not on unrelated ui writes', () async {
    final seen = <Background>[];
    final sub = settings.watchBackground().listen(seen.add);
    await pumpEventQueue();
    store.put('ui', 'workspace', {'projectId': 'x'}); // unrelated
    await pumpEventQueue();
    settings.setBackground(const ColorBackground(Color(0xFF19451C)));
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [
      Background.initial,
      const ColorBackground(Color(0xFF19451C)),
    ]);
  });
}
