import 'package:codename/activity/activity_repository.dart';

import 'dart:io';

import 'package:codename/app_theme.dart';
import 'package:codename/profiles/profile_repository.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/projects/workspace.dart';
import 'package:codename/settings/settings_repository.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  testWidgets('render', (tester) async {
    final sf = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
    await (FontLoader(
      '.AppleSystemUIFont',
    )..addFont(Future.value(ByteData.sublistView(sf)))).load();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(sf)))).load();
    final d =
        Directory('${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev')
            .listSync()
            .firstWhere(
              (e) => e.path.contains('material_symbols_icons-4.2960'),
            );
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('${d.path}/lib/fonts/MaterialSymbolsOutlined.ttf')
                    .readAsBytesSync(),
              ),
            ),
          ))
        .load();
    final store = LocalStore.inMemory();
    final dir = Directory.systemTemp.createTempSync('r');
    final projects = ProjectRepository(store);
    final profiles = ProfileRepository(store, dir, projects);
    projects.create('Website');
    projects.create('Launch');
    final me = profiles.ensureProfile();
    profiles.save(me.copyWith(name: 'Parker Hutchinson'));
    profiles.create(name: 'Grace Hopper', switchTo: false);
    final settings = SettingsRepository(store, dir, profiles: profiles);
    final tasks = TaskRepository(store, dir);
    tester.view.physicalSize = const Size(1100, 640);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Workspace(
            store: store,
            tasks: tasks,
            projects: projects,
            settings: settings,
            profiles: profiles,
            activity: ActivityRepository(store, actorId: () => null),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sidebar.png'),
    );
    await tester.tap(find.text('PH'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('dialog.png'),
    );
    await store.close();
  });
}
