import 'dart:convert';
import 'dart:io';

import 'package:codename/mcp/mcp_server.dart';
import 'package:codename/mcp/mcp_service.dart';
import 'package:codename/mcp/mcp_tools.dart';
import 'package:codename/profiles/profile_repository.dart';
import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_repository.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late ProjectRepository projects;
  late ProfileRepository profiles;
  late TaskRepository tasks;
  late McpTools tools;
  late Project launch;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mcp_test');
    store = LocalStore.inMemory();
    projects = ProjectRepository(store);
    profiles = ProfileRepository(store, dir, projects);
    tasks = TaskRepository(store, dir);
    tools = McpTools(tasks: tasks, projects: projects, profiles: profiles);
    profiles.create(name: 'Sam Lee');
    launch = projects.create('Launch');
  });

  tearDown(() async {
    await tools.dispose();
    await store.close();
    dir.deleteSync(recursive: true);
  });

  Object? run(String tool, [Map<String, Object?> args = const {}]) =>
      tools.named(tool)!.run(args);

  group('tools', () {
    test('list_projects: the shared ones and only my personal one', () {
      final me = profiles.current!;
      // Someone else's personal project stays hidden.
      profiles.create(name: 'Other', switchTo: false);
      final names = [
        for (final p in run('list_projects')! as List) (p as Map)['name'],
      ];
      expect(names, containsAll(['Launch', 'Personal']));
      expect(names.where((n) => n == 'Personal'), hasLength(1));
      expect(
        (run('list_projects')! as List).firstWhere(
          (p) => (p as Map)['name'] == 'Personal',
        )['id'],
        me.personalProjectId,
      );
    });

    test('create_project: default or given columns, unique names', () {
      final plain = run('create_project', {'name': 'Plain'})! as Map;
      expect(
        [for (final c in plain['columns'] as List) (c as Map)['name']],
        ['To do', 'In progress', 'Done'],
      );
      final custom =
          run('create_project', {
                'name': 'Custom',
                'columns': ['Backlog', 'Review', 'Shipped'],
              })!
              as Map;
      expect(
        projects.get(custom['id'] as String)!.columns.map((c) => c.title),
        ['Backlog', 'Review', 'Shipped'],
      );
      expect(projects.current().last.name, 'Custom');
      expect(
        () => run('create_project', {'name': 'launch'}),
        throwsA(isA<McpToolError>()),
      );
    });

    test('wait_for_changes reports a completion, then a move', () async {
      Future<Map> wait(Map<String, Object?> args) async =>
          (await tools.named('wait_for_changes')!.run(args))! as Map;
      final id =
          (run('create_task', {'project': launch.id, 'title': 'Ship it'})!
                  as Map)['id']
              as String;
      final start = (await wait({}))['cursor'] as int;
      await pumpEventQueue(); // the feed's watch goes live

      final pending = wait({'after': start, 'timeoutSeconds': 5});
      run('set_task_completed', {'taskId': id, 'completed': true});
      final first = await pending;
      final completed = (first['changes'] as List).single as Map;
      expect(completed['kind'], 'completed');
      expect(completed['taskId'], id);
      expect((completed['project'] as Map)['name'], 'Launch');
      expect(completed['column'], 'To do');

      run('move_task', {'taskId': id, 'column': 'Done'});
      final second = await wait({
        'after': first['cursor'],
        'timeoutSeconds': 5,
      });
      final moved = (second['changes'] as List).single as Map;
      expect(moved['kind'], 'moved');
      expect(moved['fromColumn'], 'To do');
      expect(moved['toColumn'], 'Done');

      final quiet = await wait({
        'after': second['cursor'],
        'timeoutSeconds': 0,
      });
      expect(quiet['changes'], isEmpty);
      expect(quiet['cursor'], second['cursor']);
    });

    test('create_task takes names for the project, column and person', () {
      final created =
          run('create_task', {
                'project': 'launch',
                'title': '  Write the plan ',
                'column': 'In progress',
                'assignee': 'sam lee',
                'dueDate': '2026-12-03',
                'dueTime': '14:30',
                'labels': ['docs'],
                'subtasks': ['Outline', 'Draft'],
              })!
              as Map;
      final task = tasks.get(created['id']! as String)!;
      expect(task.title, 'Write the plan');
      expect(task.status, 'doing');
      expect(task.assigneeId, profiles.current!.id);
      expect(task.dueTime, 14 * 60 + 30);
      expect(task.subtasks.map((s) => s.title), ['Outline', 'Draft']);
      // The label is kept on the project, to suggest later.
      expect(projects.get(launch.id)!.labels, ['docs']);
    });

    test('list_tasks: board order, filtered by column and completion', () {
      String make(String title, String column) =>
          (run('create_task', {
                    'project': launch.id,
                    'title': title,
                    'column': column,
                  })!
                  as Map)['id']!
              as String;
      make('B', 'todo');
      final done = make('A', 'done');
      make('C', 'todo');
      run('set_task_completed', {'taskId': done, 'completed': true});

      List<Object?> titles(Map<String, Object?> args) => [
        for (final t
            in run('list_tasks', {'project': 'Launch', ...args})! as List)
          (t as Map)['title'],
      ];
      expect(titles({}), ['B', 'C', 'A']);
      expect(titles({'column': 'To do'}), ['B', 'C']);
      expect(titles({'completed': true}), ['A']);
    });

    test('update_task changes only what is given; null clears', () {
      final id =
          (run('create_task', {
                    'project': launch.id,
                    'title': 'T',
                    'dueDate': '2026-12-03',
                    'assignee': 'Sam Lee',
                  })!
                  as Map)['id']!
              as String;
      run('update_task', {'taskId': id, 'title': 'Renamed', 'dueDate': null});
      final task = tasks.get(id)!;
      expect(task.title, 'Renamed');
      expect(task.dueDate, isNull);
      expect(task.assigneeId, isNotNull, reason: 'not given: kept');
    });

    test('move_task, subtasks and search', () {
      final id =
          (run('create_task', {'project': launch.id, 'title': 'Ship it'})!
                  as Map)['id']!
              as String;
      run('move_task', {'taskId': id, 'column': 'Done'});
      expect(tasks.get(id)!.status, 'done');

      run('add_subtasks', {
        'taskId': id,
        'titles': ['Tag release'],
      });
      final sub = tasks.get(id)!.subtasks.single;
      run('set_subtask_done', {
        'taskId': id,
        'subtaskId': sub.id,
        'done': true,
      });
      expect(tasks.get(id)!.subtasks.single.done, isTrue);

      final found = run('search_tasks', {'query': 'tag RELEASE'})! as List;
      expect([for (final t in found) (t as Map)['id']], [id]);
    });

    test('delete_task deletes it', () {
      final id =
          (run('create_task', {'project': launch.id, 'title': 'Gone'})!
                  as Map)['id']!
              as String;
      run('delete_task', {'taskId': id});
      expect(tasks.get(id), isNull);
    });

    test('mistakes are explained, listing what there is', () {
      expect(
        () => run('list_tasks', {'project': 'Nope'}),
        throwsA(
          isA<McpToolError>().having(
            (e) => e.message,
            'message',
            contains('Launch'),
          ),
        ),
      );
      expect(
        () => run('create_task', {
          'project': launch.id,
          'title': 'T',
          'dueDate': 'next week',
        }),
        throwsA(isA<McpToolError>()),
      );
      expect(
        () => run('get_task', {'taskId': 'missing'}),
        throwsA(isA<McpToolError>()),
      );
    });
  });

  group('JSON-RPC', () {
    late McpServer server;
    setUp(() => server = McpServer(tools, token: 'secret'));

    Future<Map<String, Object?>> call(
      String method, [
      Map<String, Object?>? params,
    ]) async =>
        (await server.handle({
              'jsonrpc': '2.0',
              'id': 1,
              'method': method,
              'params': ?params,
            }))!
            as Map<String, Object?>;

    test('initialize agrees on a version and offers tools', () async {
      final known = await call('initialize', {'protocolVersion': '2025-06-18'});
      expect((known['result']! as Map)['protocolVersion'], '2025-06-18');
      final unknown = await call('initialize', {
        'protocolVersion': '1999-01-01',
      });
      expect(
        (unknown['result']! as Map)['protocolVersion'],
        mcpProtocolVersions.first,
      );
      expect((known['result']! as Map)['capabilities'], contains('tools'));
    });

    test('tools/list and tools/call', () async {
      final list = await call('tools/list');
      final names = [
        for (final t in (list['result']! as Map)['tools']! as List)
          (t as Map)['name'],
      ];
      expect(names, containsAll(['list_projects', 'create_task']));

      final ok = await call('tools/call', {
        'name': 'list_projects',
        'arguments': <String, Object?>{},
      });
      expect((ok['result']! as Map)['isError'], isFalse);

      // A tool's mistake is a result the assistant reads, not an error.
      final bad = await call('tools/call', {
        'name': 'get_task',
        'arguments': {'taskId': 'missing'},
      });
      expect((bad['result']! as Map)['isError'], isTrue);
    });

    test('unknown methods are errors; notifications get no answer', () async {
      expect((await call('nope'))['error'], containsPair('code', -32601));
      expect(
        await server.handle({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }),
        isNull,
      );
    });
  });

  group('over HTTP', () {
    late McpServer server;
    late HttpClient client;

    setUp(() async {
      server = McpServer(tools, token: 'secret');
      await server.start(0);
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<(int, String)> post({
      String? token = 'secret',
      String? origin,
      String method = 'POST',
    }) async {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}$mcpPath'),
      );
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (origin != null) request.headers.set('origin', origin);
      request.headers.contentType = ContentType.json;
      if (method == 'POST') {
        request.write(
          jsonEncode({'jsonrpc': '2.0', 'id': 7, 'method': 'tools/list'}),
        );
      }
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    }

    test('answers with the token', () async {
      final (status, body) = await post();
      expect(status, 200);
      expect((jsonDecode(body) as Map)['id'], 7);
    });

    test('turns away a wrong token, a web page, and GET', () async {
      expect((await post(token: null)).$1, 401);
      expect((await post(token: 'wrong')).$1, 401);
      expect((await post(origin: 'https://evil.example')).$1, 403);
      expect((await post(origin: 'http://localhost:3000')).$1, 200);
      expect((await post(method: 'GET')).$1, 405);
    });
  });

  group('McpService', () {
    Future<int> freePort() async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    }

    test('turns on and off, and stays on across launches', () async {
      final port = await freePort();
      store.put('ui', 'mcp', {'port': port});
      final mcp = McpService(store, tools);
      expect(mcp.status.value, isA<McpOff>());

      await mcp.setEnabled(true);
      expect(mcp.status.value, isA<McpRunning>());
      final token = mcp.token;
      await mcp.dispose();

      // Next launch: on again, same token.
      final again = McpService(store, tools);
      await again.restore();
      expect(again.status.value, isA<McpRunning>());
      expect(again.token, token);

      await again.setEnabled(false);
      expect(again.status.value, isA<McpOff>());
      await again.dispose();
    });

    test('says so when the port is taken', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      store.put('ui', 'mcp', {'port': taken.port});
      final mcp = McpService(store, tools);
      await mcp.setEnabled(true);
      expect(mcp.status.value, isA<McpFailed>());
      await taken.close();
      await mcp.dispose();
    });
  });
}
