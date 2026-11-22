import 'dart:io';

import 'package:codename/app_theme.dart' show accentText, defaultAccent, isLightColor, onAccentColor;
import 'package:codename/layout.dart';
import 'package:codename/settings/background.dart';
import 'package:codename/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  test('text on the accent is near-black, white only on a very dark one', () {
    expect(onAccentColor(defaultAccent), accentText);
    expect(onAccentColor(const Color(0xFF7C73DE)), accentText); // indigo
    expect(onAccentColor(const Color(0xFF1A1A40)), Colors.white);
  });

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
    settings.setBackgroundColor(const Color(0xFF3A0F55));
    settings.setAccent(const Color(0xFFC62828));
    expect(settings.backgroundColor, const Color(0xFF3A0F55));
    settings.setBackground(const DefaultBackground());
    expect(settings.accent, const Color(0xFFC62828));
  });

  test('the background starts out as the default image over about 80% '
      'black', () {
    expect(settings.background, const DefaultBackground());
    expect(settings.backgroundColor, const Color(0xFF2D2D2D));
  });

  test('the default image is saved and read back; the old mountains load '
      'as it', () {
    settings.setBackground(const DefaultBackground());
    expect(settings.background, const DefaultBackground());
    expect(
      Background.fromJson({'type': 'mountains'}),
      const DefaultBackground(),
    );
  });

  test('a chosen color is saved and read back', () {
    settings.setBackgroundColor(const Color(0xFF003A33));
    expect(
      SettingsRepository(store, dir).backgroundColor,
      const Color(0xFF003A33),
    );
  });

  test('choosing an image keeps the color, and choosing a color keeps the '
      'image', () async {
    settings.setBackgroundColor(const Color(0xFF003A33));
    final image = await settings.setBackgroundImage(picked('a.png').path);
    settings.setBackground(const DefaultBackground());
    expect(settings.backgroundColor, const Color(0xFF003A33));
    settings.setBackground(image);
    settings.setBackgroundColor(const Color(0xFF6D1616));
    expect(settings.background, image);
    settings.setBackground(null);
    expect(settings.background, isNull);
    expect(settings.backgroundColor, const Color(0xFF6D1616));
  });

  test('an old saved color becomes the color, with no image', () {
    store.put('ui', 'settings', {
      'background': {'type': 'color', 'color': 0xFF003A33},
    });
    expect(settings.background, isNull);
    expect(settings.backgroundColor, const Color(0xFF003A33));
    // Kept when the image changes.
    settings.setBackground(const DefaultBackground());
    expect(settings.backgroundColor, const Color(0xFF003A33));
  });

  test('a saved color from the old brighter list loads as its darker one', () {
    expect(
      backgroundColorFromJson({
        'background': {'type': 'color', 'color': 0xFF00695C},
      }),
      const Color(0xFF003A33),
    );
    expect(
      backgroundColorFromJson({'backgroundColor': 0xFF00695C}),
      const Color(0xFF003A33),
    );
  });

  test('the background choices are the default and a dark version of each '
      'accent, near-black, off-white and a light version of each accent', () {
    expect(backgroundColors.first, surfaceColor);
    expect(backgroundColors, hasLength(35));
    // Dark through near-black; then off-white and the light ones, light
    // enough that the app turns its text dark.
    for (final c in backgroundColors.take(18)) {
      expect(c.computeLuminance(), lessThan(0.05), reason: '$c');
    }
    for (final c in backgroundColors.skip(18)) {
      expect(isLightColor(c), isTrue, reason: '$c');
    }
  });

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

    settings.setBackground(null);
    expect(settings.backgroundFile(second.fileName).existsSync(), isFalse);
  });

  test('other settings in the same record are kept', () {
    store.put('ui', 'settings', {'other': 1});
    settings.setBackgroundColor(const Color(0xFF121212));
    settings.setBackground(const DefaultBackground());
    expect(store.get('ui', 'settings')!['other'], 1);
  });

  test('unknown or broken values mean no image and the initial color', () {
    for (final json in [
      null,
      <String, Object?>{},
      {'type': 'video'},
      {'type': 'image', 'file': ''},
      {'type': 'color', 'color': 'blue'},
    ]) {
      expect(Background.fromJson(json), isNull);
      expect(
        backgroundColorFromJson({'background': json}),
        initialBackgroundColor,
      );
    }
  });

  test('watchBackground emits on change, not on unrelated ui writes', () async {
    final seen = <Background?>[];
    final sub = settings.watchBackground().listen(seen.add);
    await pumpEventQueue();
    store.put('ui', 'workspace', {'projectId': 'x'}); // unrelated
    await pumpEventQueue();
    settings.setBackgroundColor(const Color(0xFF19451C)); // not the image
    settings.setBackground(null);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [const DefaultBackground(), null]);
  });
}
