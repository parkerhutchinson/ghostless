import 'package:characters/characters.dart';

import 'dart:async';

import '../data/ids.dart';
import '../comments/comment.dart';
import '../comments/comment_repository.dart';
import '../profiles/profile.dart';
import '../profiles/profile_repository.dart';
import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../tasks/due_date.dart';
import '../tasks/project_labels.dart' show maxLabelLength;
import '../tasks/task.dart';
import '../tasks/task_repository.dart';
import '../reminders/reminders.dart' show canSetReminder;
import 'mcp_files.dart';
import 'task_change_feed.dart';
import '../tasks/image_compression.dart';

/// Something a tool call got wrong (an unknown task, a bad date): told to
/// the AI assistant so it can fix the call. Not a crash.
final class McpToolError implements Exception {
  const McpToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One tool the MCP server offers: its [name], what it does
/// ([description], read by the AI assistant), the arguments it takes (a
/// JSON Schema) and what it does with them ([run], returning JSON).
final class McpTool {
  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.run,
    this.readOnly = false,
    this.destructive = false,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final FutureOr<Object?> Function(Map<String, Object?> args) run;

  /// Only looks: changes nothing.
  final bool readOnly;

  /// Deletes something (MCP clients ask before running these).
  final bool destructive;

  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': {
      'title': title,
      'readOnlyHint': readOnly,
      'destructiveHint': destructive,
      'openWorldHint': false,
    },
  };
}

/// The app's tools for AI assistants: reading and changing projects and
/// tasks through the same repositories the screens use, as the profile
/// using the app on this Mac (whose personal project is the only one it
/// sees; changes show in Activity as theirs).
final class McpTools {
  McpTools({
    required this.tasks,
    required this.projects,
    required this.profiles,
    this.comments,
  });

  /// Task comments; without it (tests), tasks have none to read or add.
  final CommentRepository? comments;

  final TaskRepository tasks;
  final ProjectRepository projects;
  final ProfileRepository profiles;

  /// Recent task changes, for wait_for_changes. Starts watching on first
  /// use.
  late final TaskChangeFeed changes = TaskChangeFeed(tasks);

  Future<void> dispose() async => _feedStarted ? changes.dispose() : null;
  bool _feedStarted = false;

  late final List<McpTool> all = [
    McpTool(
      name: 'list_projects',
      title: 'List projects',
      description:
          'Lists the projects (boards), in sidebar order: id, name, whether '
          'it is the personal project, whether the person using the app '
          'starred it (favorite), its status (onTrack, atRisk, offTrack, '
          'onHold, or null for none), its description (Markdown), its columns '
          '(left to right) and how many tasks it has.',
      inputSchema: _object({}),
      readOnly: true,
      run: (_) => [for (final p in _projects) _projectJson(p)],
    ),
    McpTool(
      name: 'create_project',
      title: 'Create project',
      description:
          'Creates a shared project (board) at the bottom of the sidebar, '
          'with the next color in turn. Its columns are To do, In progress '
          'and Done unless columns are given. Returns it.',
      inputSchema: _object(
        {
          'name': _string('The project\'s name.'),
          'description': _string(
            'What the project is about, in Markdown ($_markdownSubset). '
            'Shown on its dashboard.',
          ),
          'columns': _strings('Its columns\' names, left to right.'),
        },
        required: ['name'],
      ),
      run: (args) {
        final name = _requiredString(args, 'name').trim();
        if (name.isEmpty) throw const McpToolError('name is required.');
        if (_projects.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
          throw McpToolError('There\'s already a project "$name".');
        }
        final columnNames = _stringList(args['columns']);
        var project = projects.create(
          name,
          description: _optionalString(args, 'description')?.trim() ?? '',
        );
        if (columnNames.isNotEmpty) {
          project = project.copyWith(
            columns: [for (final c in columnNames) TaskColumn(newId(), c)],
          );
          projects.save(project);
        }
        return _projectJson(project);
      },
    ),
    McpTool(
      name: 'update_project',
      title: 'Update project',
      description:
          'Renames a shared project or changes its description or status. Only the '
          'fields given change. The personal project can\'t be edited. '
          'Returns it.',
      inputSchema: _object(
        {
          'project': _project,
          'name': _string('New name.'),
          'description': _string(
            'New description, in Markdown ($_markdownSubset). An empty '
            'string clears it.',
          ),
          'status': {
            'type': ['string', 'null'],
            'enum': [...ProjectStatus.values.map((s) => s.name), null],
            'description':
                'How the project is going: onTrack, atRisk, offTrack or '
                'onHold. null clears it.',
          },
        },
        required: ['project'],
      ),
      run: (args) {
        final project = _projectArg(args);
        if (project.isPersonal) {
          throw const McpToolError('The personal project can\'t be edited.');
        }
        final name = _optionalString(args, 'name')?.trim();
        if (name != null) {
          if (name.isEmpty) throw const McpToolError('name can\'t be empty.');
          if (_projects.any(
            (p) =>
                p.id != project.id &&
                p.name.toLowerCase() == name.toLowerCase(),
          )) {
            throw McpToolError('There\'s already a project "$name".');
          }
        }
        var updated = project.copyWith(
          name: name,
          description: _optionalString(args, 'description')?.trim(),
        );
        if (args.containsKey('status')) {
          final value = args['status'];
          final status = ProjectStatus.from(value);
          if (value != null && status == null) {
            throw McpToolError(
              'Unknown status "$value": use onTrack, atRisk, offTrack or '
              'onHold, or null to clear it.',
            );
          }
          updated = updated.copyWith(status: status);
        }
        projects.save(updated);
        return _projectJson(updated);
      },
    ),
    McpTool(
      name: 'list_people',
      title: 'List people',
      description:
          'Lists the people (profiles) tasks can be assigned to, with which '
          'one is using the app.',
      inputSchema: _object({}),
      readOnly: true,
      run: (_) {
        final me = profiles.current?.id;
        return [for (final p in profiles.all()) _personJson(p, me: me)];
      },
    ),
    McpTool(
      name: 'create_person',
      title: 'Create person',
      description:
          'Adds a person (profile) tasks can be assigned to, with their own '
          'personal project. Doesn\'t switch the app to them. Returns them.',
      inputSchema: _object(
        {
          'name': _string('Their full name.'),
          'department': _string('Their department.'),
          'jobTitle': _string('Their job title.'),
          'description': _string('A short line about them.'),
        },
        required: ['name'],
      ),
      run: (args) {
        final name = _requiredString(args, 'name').trim();
        if (name.isEmpty) throw const McpToolError('name is required.');
        if (profiles.all().any(
          (p) => p.fullName.toLowerCase() == name.toLowerCase(),
        )) {
          throw McpToolError('There\'s already a person named "$name".');
        }
        var person = profiles.create(name: name, switchTo: false);
        person = person.copyWith(
          department: _optionalString(args, 'department')?.trim(),
          jobTitle: _optionalString(args, 'jobTitle')?.trim(),
          description: _optionalString(args, 'description')?.trim(),
        );
        profiles.save(person);
        return _personJson(person, me: profiles.current?.id);
      },
    ),
    McpTool(
      name: 'list_tasks',
      title: 'List tasks',
      description:
          'Lists a project\'s tasks in board order (by column, then '
          'position), as summaries. Use get_task for a task\'s description '
          'and subtasks.',
      inputSchema: _object(
        {
          'project': _project,
          'column': _string('Only this column (its id or name).'),
          'completed': _boolean(
            'Only completed tasks (true) or only open ones (false); both '
            'when left out.',
          ),
          'assignee': _string(
            'Only tasks assigned to this person (id or name), or '
            '"unassigned".',
          ),
        },
        required: ['project'],
      ),
      readOnly: true,
      run: (args) {
        final project = _projectArg(args);
        final column = switch (args['column']) {
          final String c => _column(project, c).id,
          _ => null,
        };
        final completed = args['completed'] as bool?;
        final assignee = switch (args['assignee']) {
          final String a when a.toLowerCase() == 'unassigned' => '',
          final String a => _person(a),
          _ => null,
        };
        return [
          for (final t in _boardOrder(project))
            if (column == null ||
                project.columnFor(t.placementIn(project.id).status) == column)
              if (completed == null || t.isCompletedIn(project.id) == completed)
                if (assignee == null || (t.assigneeId ?? '') == assignee)
                  _taskSummary(t, project),
        ];
      },
    ),
    McpTool(
      name: 'search_tasks',
      title: 'Search tasks',
      description:
          'Finds tasks whose title, description, labels or subtasks contain '
          'the text (ignoring case), across every project or in one.',
      inputSchema: _object(
        {'query': _string('The text to look for.'), 'project': _project},
        required: ['query'],
      ),
      readOnly: true,
      run: (args) {
        final query = _requiredString(args, 'query').toLowerCase();
        final only = args['project'] == null ? null : _projectArg(args);
        final visible = {for (final p in _projects) p.id: p};
        bool matches(Task t) => [
          t.title,
          t.description,
          ...t.tags,
          for (final s in t.subtasks) s.title,
        ].any((text) => text.toLowerCase().contains(query));
        return [
          for (final t in tasks.current())
            if (visible[t.originId] case final origin?)
              if (only == null || t.isIn(only.id))
                if (matches(t)) _taskSummary(t, only ?? origin),
        ];
      },
    ),
    McpTool(
      name: 'get_task',
      title: 'Get task',
      description:
          'Everything about one task: title, description (Markdown), column '
          'and completion on each of its projects, assignee, due date, '
          'labels, subtasks (with ids), attachment names and comments '
          '(oldest first).',
      inputSchema: _object({'taskId': _taskId}, required: ['taskId']),
      readOnly: true,
      run: (args) => _taskDetail(_task(args)),
    ),
    McpTool(
      name: 'create_task',
      title: 'Create task',
      description:
          'Creates a task at the bottom of a column (the first column by '
          'default) in a project. Returns it.',
      inputSchema: _object(
        {
          'project': _project,
          'title': _string('The task\'s title.'),
          'description': _string('Details, in Markdown ($_markdownSubset).'),
          'column': _string('The column to put it in (its id or name).'),
          'assignee': _string('Who it\'s for (a person\'s id or name).'),
          'dueDate': _string('Due day, YYYY-MM-DD.'),
          'dueTime': _string(
            'Due time of day, HH:MM (24-hour); needs dueDate.',
          ),
          'reminder': _reminderSchema,
          'labels': _strings(
            'Labels to put on it (each at most $maxLabelLength characters).',
          ),
          'subtasks': _strings('Subtask titles, in order.'),
          'image': mcpFileSchema('The card image, shown on the card.'),
          'attachments': {
            'type': 'array',
            'description': 'Files to attach (images or PDFs), in order.',
            'items': mcpFileSchema(
              'An image or PDF to attach.',
              allowPdf: true,
            ),
          },
        },
        required: ['project', 'title'],
      ),
      run: (args) {
        // Everything checked before any file is read or stored.
        final project = _projectArg(args);
        final title = _requiredString(args, 'title').trim();
        if (title.isEmpty) throw const McpToolError('The title is empty.');
        final dueDate = _day(args['dueDate']);
        final dueTime = dueDate == null ? null : _time(args['dueTime']);
        final reminder = _reminderArg(args['reminder']);
        if (reminder != null && dueDate == null) {
          throw const McpToolError('Set a dueDate to have a reminder.');
        }
        final labels = _labels(args['labels']);
        final assignee =
            // On a personal project, always its owner.
            project.ownerId ??
            switch (args['assignee']) {
              final String a => _person(a),
              _ => null,
            };
        if (reminder != null &&
            !canSetReminder(assigneeId: assignee, me: profiles.current?.id)) {
          throw const McpToolError(_reminderNotMine);
        }
        Map<String, Object?> create({
          List<String> images = const [],
          List<Attachment> attachments = const [],
        }) {
          final created = tasks.create(
            title: title,
            description: (args['description'] as String? ?? '').trim(),
            status: switch (args['column']) {
              final String c => _column(project, c).id,
              _ => project.columns.first.id,
            },
            tags: labels,
            images: images,
            attachments: attachments,
            originId: project.id,
            dueDate: dueDate,
            dueTime: dueTime,
            subtasks: [
              for (final s in _stringList(args['subtasks']))
                Subtask(id: newId(), title: s),
            ],
            assigneeId: assignee,
            reminder: reminder,
          );
          projects.addLabels(project.id, labels);
          return _taskDetail(created);
        }

        if (args['image'] == null && args['attachments'] == null) {
          return create();
        }
        // Files: read (and checked) first, then stored.
        return () async {
          final image = await _readImage(args['image']);
          final attachments = await _readAttachments(
            args['attachments'],
            'attachments',
          );
          return create(
            images: [if (image != null) await _store(image)],
            attachments: await _storeAttachments(attachments),
          );
        }();
      },
    ),
    McpTool(
      name: 'update_task',
      title: 'Update task',
      description:
          'Changes a task\'s details; only the fields given change. Pass '
          'null for assignee or dueDate to clear it. labels replaces all its '
          'labels.',
      inputSchema: _object(
        {
          'taskId': _taskId,
          'title': _string('New title.'),
          'description': _string(
            'New description, in Markdown ($_markdownSubset).',
          ),
          'assignee': {
            'type': ['string', 'null'],
            'description': 'A person\'s id or name; null to unassign.',
          },
          'dueDate': {
            'type': ['string', 'null'],
            'description': 'YYYY-MM-DD; null to remove the due date.',
          },
          'dueTime': {
            'type': ['string', 'null'],
            'description': 'HH:MM (24-hour); null for no time.',
          },
          'reminder': {
            ..._reminderSchema,
            'type': ['integer', 'null'],
          },
          'labels': _strings('Its labels (replacing the ones it has).'),
          'image': {
            ...mcpFileSchema(
              'A new card image, replacing the one it has; null to remove it.',
            ),
            'type': ['object', 'null'],
          },
          'addAttachments': {
            'type': 'array',
            'description':
                'Files to attach (images or PDFs), after the others.',
            'items': mcpFileSchema(
              'An image or PDF to attach.',
              allowPdf: true,
            ),
          },
          'removeAttachments': _strings(
            'Names of attachments to remove (as get_task lists them).',
          ),
        },
        required: ['taskId'],
      ),
      run: (args) {
        final task = _updated(_task(args), args);
        final files =
            args.containsKey('image') ||
            args['addAttachments'] != null ||
            args['removeAttachments'] != null;
        if (!files) {
          _saveUpdated(task, args);
          return _taskDetail(tasks.get(task.id) ?? task);
        }
        return _updateFiles(task, args);
      },
    ),
    McpTool(
      name: 'move_task',
      title: 'Move task',
      description:
          'Moves a task to a column on one of its projects\' boards (its '
          'origin project by default), at the top or bottom.',
      inputSchema: _object(
        {
          'taskId': _taskId,
          'column': _string('The column (its id or name).'),
          'project': _string(
            'Which board, for a task in several projects (id or name).',
          ),
          'position': {
            'type': 'string',
            'enum': ['top', 'bottom'],
            'description': 'Where in the column; bottom by default.',
          },
        },
        required: ['taskId', 'column'],
      ),
      run: (args) {
        final task = _task(args);
        final board = _board(task, args);
        final column = _column(board, _requiredString(args, 'column'));
        tasks.move(
          task.id,
          column.id,
          args['position'] == 'top' ? 0 : 1 << 30,
          projectId: board.id,
        );
        return _taskDetail(tasks.get(task.id)!);
      },
    ),
    McpTool(
      name: 'set_task_completed',
      title: 'Complete task',
      description:
          'Checks a task off (or back on) on one of its projects\' boards (its '
          'origin project by default). It stays in its column.',
      inputSchema: _object(
        {
          'taskId': _taskId,
          'completed': _boolean('true to check it off, false to reopen it.'),
          'project': _string(
            'Which board, for a task in several projects (id or name).',
          ),
        },
        required: ['taskId', 'completed'],
      ),
      run: (args) {
        final task = _task(args);
        final board = _board(task, args);
        final done = args['completed'];
        if (done is! bool) {
          throw const McpToolError('completed must be true or false.');
        }
        tasks.save(task.withCompleted(board.id, done));
        return _taskDetail(tasks.get(task.id)!);
      },
    ),
    McpTool(
      name: 'add_subtasks',
      title: 'Add subtasks',
      description: 'Adds subtasks to the end of a task\'s list.',
      inputSchema: _object(
        {'taskId': _taskId, 'titles': _strings('Their titles, in order.')},
        required: ['taskId', 'titles'],
      ),
      run: (args) {
        final task = _task(args);
        final titles = _stringList(args['titles']);
        if (titles.isEmpty) throw const McpToolError('No titles given.');
        tasks.save(
          task.copyWith(
            subtasks: [
              ...task.subtasks,
              for (final t in titles) Subtask(id: newId(), title: t),
            ],
          ),
        );
        return _taskDetail(tasks.get(task.id)!);
      },
    ),
    McpTool(
      name: 'set_subtask_done',
      title: 'Check off subtask',
      description: 'Checks a subtask off, or back on.',
      inputSchema: _object(
        {
          'taskId': _taskId,
          'subtaskId': _string('The subtask\'s id (from get_task).'),
          'done': _boolean('true to check it off, false to uncheck it.'),
        },
        required: ['taskId', 'subtaskId', 'done'],
      ),
      run: (args) {
        final task = _task(args);
        final id = _requiredString(args, 'subtaskId');
        if (!task.subtasks.any((s) => s.id == id)) {
          throw McpToolError('The task has no subtask "$id".');
        }
        final done = args['done'] == true;
        tasks.save(
          task.copyWith(
            subtasks: [
              for (final s in task.subtasks)
                s.id == id ? s.copyWith(done: done) : s,
            ],
          ),
        );
        return _taskDetail(tasks.get(task.id)!);
      },
    ),
    McpTool(
      name: 'wait_for_changes',
      title: 'Wait for changes',
      description:
          'Reports changes to tasks (someone created, completed, reopened, '
          'moved, edited or deleted one), oldest first, each with a seq '
          'number. Pass the cursor from the last call as after; if nothing '
          'has changed since, it waits up to timeoutSeconds for something '
          'to. Leave after out to just get the current cursor.',
      inputSchema: _object({
        'after': {
          'type': 'integer',
          'description': 'The cursor from the last call.',
        },
        'timeoutSeconds': {
          'type': 'number',
          'description':
              'How long to wait for a change: 0 to 60, 25 by '
              'default.',
        },
      }),
      readOnly: true,
      run: (args) async {
        _feedStarted = true;
        final feed = changes;
        final after = switch (args['after']) {
          null => null,
          final num n => n.toInt(),
          _ => throw const McpToolError('after must be a number.'),
        };
        if (after == null) return {'cursor': feed.latest, 'changes': []};
        final seconds = switch (args['timeoutSeconds']) {
          null => 25,
          final num n => n.clamp(0, 60),
          _ => throw const McpToolError('timeoutSeconds must be a number.'),
        };
        final events = await feed.wait(
          after,
          Duration(milliseconds: (seconds * 1000).round()),
        );
        final visible = {for (final p in _projects) p.id: p};
        return {
          'cursor': events.isEmpty ? after : events.last.seq,
          'changes': [
            for (final e in events)
              if (_eventVisible(e, visible)) _eventJson(e, visible),
          ],
        };
      },
    ),
    McpTool(
      name: 'add_comment',
      title: 'Add comment',
      description:
          'Comments on a task, as the person using the app. The task\'s '
          'assignee hears about it in Activity (unless it\'s them). Returns '
          'the comment.',
      inputSchema: _object(
        {
          'taskId': _taskId,
          'body': _string(
            'What to say, in Markdown: paragraphs (a blank line between), '
            '**bold** and [links](https://example.com) only; anything else '
            'is kept as plain text.',
          ),
        },
        required: ['taskId', 'body'],
      ),
      run: (args) {
        final task = _task(args);
        final repo = comments;
        final me = profiles.current?.id;
        if (repo == null || me == null) {
          throw const McpToolError('Comments aren\'t available.');
        }
        final comment = repo.add(
          taskId: task.id,
          authorId: me,
          body: _requiredString(args, 'body'),
        );
        if (comment == null) throw const McpToolError('body is empty.');
        return {
          'id': comment.id,
          'taskId': task.id,
          'body': comment.body,
          'createdAt': comment.createdAt.toUtc().toIso8601String(),
        };
      },
    ),
    McpTool(
      name: 'delete_task',
      title: 'Delete task',
      description:
          'Deletes a task from every project it\'s in, with its subtasks and '
          'attachments. This can\'t be undone.',
      inputSchema: _object({'taskId': _taskId}, required: ['taskId']),
      destructive: true,
      run: (args) {
        final task = _task(args);
        tasks.delete(task.id);
        return {'deleted': task.id, 'title': task.title};
      },
    ),
  ];

  /// The tool named [name], or null.
  McpTool? named(String name) => all.where((t) => t.name == name).firstOrNull;

  // Lookups. Projects and people can be named by id or (ignoring case)
  // name; only what the profile using the app can see.

  List<Project> get _projects =>
      visibleProjects(projects.current(), profiles.current?.id);

  Project _projectArg(Map<String, Object?> args) =>
      _findProject(_requiredString(args, 'project'));

  Project _findProject(String key) {
    final visible = _projects;
    return visible.where((p) => p.id == key).firstOrNull ??
        visible
            .where((p) => p.name.toLowerCase() == key.trim().toLowerCase())
            .firstOrNull ??
        (throw McpToolError(
          'No project "$key". Projects: '
          '${visible.map((p) => p.name).join(', ')}.',
        ));
  }

  /// The board a call is about: the project named in args (one the task
  /// is in), else the task's origin.
  Project _board(Task task, Map<String, Object?> args) {
    if (args['project'] case final String key) {
      final p = _findProject(key);
      if (!task.isIn(p.id)) {
        throw McpToolError('The task isn\'t in "${p.name}".');
      }
      return p;
    }
    return projects.get(task.originId) ??
        (throw const McpToolError('The task\'s project is gone.'));
  }

  TaskColumn _column(Project project, String key) =>
      project.columns.where((c) => c.id == key).firstOrNull ??
      project.columns
          .where((c) => c.title.toLowerCase() == key.trim().toLowerCase())
          .firstOrNull ??
      (throw McpToolError(
        '"${project.name}" has no column "$key". Columns: '
        '${project.columns.map((c) => c.title).join(', ')}.',
      ));

  String _person(String key) {
    final all = profiles.all();
    return (all.where((p) => p.id == key).firstOrNull ??
            all
                .where(
                  (p) =>
                      p.displayName.toLowerCase() == key.trim().toLowerCase(),
                )
                .firstOrNull ??
            (throw McpToolError(
              'No person "$key". People: '
              '${all.map((p) => p.displayName).join(', ')}.',
            )))
        .id;
  }

  /// [task] with update_task's text, people, date and label changes (not
  /// saved).
  Task _updated(Task task, Map<String, Object?> args) {
    if (args['title'] case final String title) {
      if (title.trim().isEmpty) {
        throw const McpToolError('The title is empty.');
      }
      task = task.copyWith(title: title.trim());
    }
    if (args['description'] case final String d) {
      task = task.copyWith(description: d.trim());
    }
    if (args.containsKey('assignee') && !_isPersonal(task)) {
      final assignee = switch (args['assignee']) {
        final String a => _person(a),
        _ => null,
      };
      task = task.copyWith(
        assigneeId: assignee,
        // A reminder is the assignee's own: someone new starts without.
        reminder: assignee == task.assigneeId ? task.reminder : null,
      );
    }
    if (args.containsKey('dueDate')) {
      final day = _day(args['dueDate']);
      task = task.copyWith(
        dueDate: day,
        dueTime: day == null ? null : task.dueTime,
      );
    }
    if (args.containsKey('dueTime')) {
      if (task.dueDate == null && args['dueTime'] != null) {
        throw const McpToolError('Set a dueDate before a dueTime.');
      }
      task = task.copyWith(dueTime: _time(args['dueTime']));
    }
    if (args.containsKey('reminder')) {
      final reminder = _reminderArg(args['reminder']);
      if (reminder != null && task.dueDate == null) {
        throw const McpToolError('Set a dueDate to have a reminder.');
      }
      if (reminder != null &&
          !canSetReminder(
            assigneeId: task.assigneeId,
            me: profiles.current?.id,
          )) {
        throw const McpToolError(_reminderNotMine);
      }
      task = task.copyWith(reminder: reminder);
    }
    if (args['labels'] != null) {
      final labels = _labels(args['labels']);
      task = task.copyWith(tags: labels);
    }
    return task;
  }

  /// Saves an updated task; new labels join its project's.
  void _saveUpdated(Task task, Map<String, Object?> args) {
    tasks.save(task);
    if (args['labels'] != null) projects.addLabels(task.originId, task.tags);
  }

  /// update_task's card image and attachment changes, then saves [task]:
  /// new files are read (and checked) before anything is stored, and the
  /// files it no longer uses are deleted.
  Future<Map<String, Object?>> _updateFiles(
    Task task,
    Map<String, Object?> args,
  ) async {
    final remove = _stringList(args['removeAttachments']).toSet();
    final unknown = remove.difference({
      for (final a in task.attachments) a.name,
    });
    if (unknown.isNotEmpty) {
      throw McpToolError('No attachment named "${unknown.first}".');
    }
    final image = await _readImage(args['image']);
    final added = await _readAttachments(
      args['addAttachments'],
      'addAttachments',
    );
    final unused = <String>[];
    var images = task.images;
    if (args.containsKey('image')) {
      unused.addAll(task.images);
      images = [if (image != null) await _store(image)];
    }
    final kept = [
      for (final a in task.attachments)
        if (!remove.contains(a.name)) a,
    ];
    unused.addAll([
      for (final a in task.attachments)
        if (remove.contains(a.name)) a.file,
    ]);
    task = task.copyWith(
      images: images,
      attachments: [...kept, ...await _storeAttachments(added)],
    );
    _saveUpdated(task, args);
    unused.forEach(tasks.deleteImage);
    return _taskDetail(tasks.get(task.id) ?? task);
  }

  Future<McpFile?> _readImage(Object? spec) async =>
      spec == null ? null : await readMcpFile(spec, argument: 'image');

  Future<List<McpFile>> _readAttachments(Object? specs, String argument) async {
    if (specs == null) return const [];
    if (specs is! List) throw McpToolError('$argument must be a list.');
    return [
      for (final (i, spec) in specs.indexed)
        await readMcpFile(spec, argument: '$argument[$i]', allowPdf: true),
    ];
  }

  Future<String> _store(McpFile file) =>
      tasks.addImageBytes(file.bytes, file.extension);

  Future<List<Attachment>> _storeAttachments(List<McpFile> files) async => [
    for (final f in files)
      if (await _store(f) case final stored)
        // Named for what it's kept as (a PNG photo kept as JPEG).
        Attachment(file: stored, name: withExtensionOf(f.name, stored)),
  ];

  Task _task(Map<String, Object?> args) {
    final id = _requiredString(args, 'taskId');
    final task = tasks.get(id);
    final visible = {for (final p in _projects) p.id};
    if (task == null || !task.projectIds.any(visible.contains)) {
      throw McpToolError('No task "$id".');
    }
    return task;
  }

  bool _isPersonal(Task t) => projects.get(t.originId)?.isPersonal ?? false;

  List<Task> _boardOrder(Project project) {
    final index = {for (final (i, c) in project.columns.indexed) c.id: i};
    int column(Task t) =>
        index[project.columnFor(t.placementIn(project.id).status)] ?? 0;
    return tasks.inProject(project.id)..sort((a, b) {
      final byColumn = column(a).compareTo(column(b));
      return byColumn != 0
          ? byColumn
          : a
                .placementIn(project.id)
                .order
                .compareTo(b.placementIn(project.id).order);
    });
  }

  // As JSON.

  bool _eventVisible(TaskChangeEvent e, Map<String, Project> visible) =>
      e.projectId != null
      ? visible.containsKey(e.projectId)
      : switch (tasks.get(e.taskId)) {
          final t? => t.projectIds.any(visible.containsKey),
          null => true,
        };

  Map<String, Object?> _eventJson(
    TaskChangeEvent e,
    Map<String, Project> visible,
  ) {
    final board = visible[e.projectId];
    String? column(String? status) => board == null || status == null
        ? null
        : board.columns
              .firstWhere((c) => c.id == board.columnFor(status))
              .title;
    return {
      'seq': e.seq,
      'kind': e.kind,
      'taskId': e.taskId,
      'title': e.title,
      'at': e.at.toIso8601String(),
      if (board != null) 'project': {'id': board.id, 'name': board.name},
      if (board != null && e.kind != 'moved')
        if (tasks.get(e.taskId) case final t? when t.isIn(board.id))
          'column': column(t.placementIn(board.id).status),
      if (e.kind == 'moved') ...{
        'fromColumn': column(e.fromStatus),
        'toColumn': column(e.toStatus),
      },
      if (e.changes.isNotEmpty) 'changes': e.changes,
    };
  }

  Map<String, Object?> _projectJson(Project p) => {
    'id': p.id,
    'name': p.name,
    'personal': p.isPersonal,
    'favorite': profiles.current?.isFavorite(p.id) ?? false,
    'status': p.status?.name,
    'description': p.description,
    'columns': [
      for (final c in p.columns) {'id': c.id, 'name': c.title},
    ],
    'taskCount': tasks.inProject(p.id).length,
  };

  Map<String, Object?> _personJson(Profile p, {String? me}) => {
    'id': p.id,
    'name': p.displayName,
    if (p.department.isNotEmpty) 'department': p.department,
    if (p.jobTitle.isNotEmpty) 'jobTitle': p.jobTitle,
    'isMe': p.id == me,
  };

  String? _personName(String? id) =>
      id == null ? null : profiles.get(id)?.displayName;

  Map<String, Object?> _due(Task t) => {
    'dueDate': t.dueDate == null ? null : formatDay(t.dueDate!),
    'dueTime': t.dueDate == null || t.dueTime == null
        ? null
        : formatStoredTime(t.dueTime!),
    'reminder': t.dueDate == null ? null : t.reminder,
  };

  static const _reminderSchema = {
    'type': 'integer',
    'minimum': 0,
    'description':
        'Remind the assignee (a macOS notification) this many minutes '
        'before it\'s due: 0 at the due time, 60 an hour before, 1440 a '
        'day before. A task due any time that day counts as due at 9 AM. '
        'Needs dueDate and the task assigned to you (the current '
        'person); null for no reminder.',
  };

  /// A reminder in minutes before, or null for none.
  int? _reminderArg(Object? value) => switch (value) {
    null => null,
    final num m when m >= 0 && m == m.roundToDouble() => m.toInt(),
    _ => throw const McpToolError(
      'reminder must be a whole number of minutes, 0 or more.',
    ),
  };

  Map<String, Object?> _taskSummary(Task t, Project board) {
    final status = board.columnFor(t.placementIn(board.id).status);
    return {
      'id': t.id,
      'title': t.title,
      'project': board.name,
      'column': board.columns.firstWhere((c) => c.id == status).title,
      'completed': t.isCompletedIn(board.id),
      'assignee': _personName(t.assigneeId),
      ..._due(t),
      'labels': t.tags,
      if (t.subtasks.isNotEmpty)
        'subtasks':
            '${t.subtasks.where((s) => s.done).length}/${t.subtasks.length} done',
    };
  }

  Map<String, Object?> _taskDetail(Task t) => {
    'id': t.id,
    'title': t.title,
    'description': t.description,
    'assignee': t.assigneeId == null
        ? null
        : {'id': t.assigneeId, 'name': _personName(t.assigneeId)},
    ..._due(t),
    'labels': t.tags,
    'originProject': projects.get(t.originId)?.name,
    'projects': [
      for (final id in t.projectIds)
        if (projects.get(id) case final p?)
          {
            'id': p.id,
            'name': p.name,
            'column': p.columns
                .firstWhere(
                  (c) => c.id == p.columnFor(t.placementIn(id).status),
                )
                .title,
            'completed': t.isCompletedIn(id),
          },
    ],
    'subtasks': [
      for (final s in t.subtasks)
        {'id': s.id, 'title': s.title, 'done': s.done},
    ],
    'cardImage': t.images.isNotEmpty,
    'attachments': [for (final a in t.attachments) a.name],
    'comments': [
      for (final c in comments?.forTask(t.id) ?? const <Comment>[])
        {
          'id': c.id,
          'author': {'id': c.authorId, 'name': _personName(c.authorId)},
          'body': c.body,
          'createdAt': c.createdAt.toUtc().toIso8601String(),
        },
    ],
    'createdAt': t.createdAt.toUtc().toIso8601String(),
  };
}

// Argument reading.

String _requiredString(Map<String, Object?> args, String key) =>
    switch (args[key]) {
      final String s when s.isNotEmpty => s,
      _ => throw McpToolError('$key is required.'),
    };

/// [key]'s text, or null when it isn't given; anything but text is a
/// mistake.
String? _optionalString(Map<String, Object?> args, String key) =>
    switch (args[key]) {
      null => null,
      final String s => s,
      _ => throw McpToolError('$key should be text.'),
    };

List<String> _stringList(Object? value) => switch (value) {
  null => const [],
  final List list => [
    for (final v in list)
      if (v is String && v.trim().isNotEmpty) v.trim(),
  ],
  _ => throw const McpToolError('Expected a list of text.'),
};

/// Labels from [value], each at most [maxLabelLength] characters.
List<String> _labels(Object? value) {
  final labels = _stringList(value);
  for (final l in labels) {
    if (l.characters.length > maxLabelLength) {
      throw McpToolError(
        'The label "$l" is too long: labels can be at most '
        '$maxLabelLength characters.',
      );
    }
  }
  return labels;
}

DateTime? _day(Object? value) => switch (value) {
  null => null,
  final String s =>
    parseDay(s.trim()) ??
        (throw McpToolError('"$s" isn\'t a date like 2026-12-31.')),
  _ => throw const McpToolError('dueDate must be text like 2026-12-31.'),
};

int? _time(Object? value) => switch (value) {
  null => null,
  final String s =>
    parseStoredTime(s.trim()) ??
        (throw McpToolError('"$s" isn\'t a time like 14:30.')),
  _ => throw const McpToolError('dueTime must be text like 14:30.'),
};

// JSON Schema pieces.

Map<String, Object?> _object(
  Map<String, Object?> properties, {
  List<String> required = const [],
}) => {
  'type': 'object',
  'properties': properties,
  if (required.isNotEmpty) 'required': required,
};

Map<String, Object?> _string(String description) => {
  'type': 'string',
  'description': description,
};

Map<String, Object?> _boolean(String description) => {
  'type': 'boolean',
  'description': description,
};

Map<String, Object?> _strings(String description) => {
  'type': 'array',
  'items': {'type': 'string'},
  'description': description,
};

final _project = _string('The project (its id or name).');
final _taskId = _string('The task\'s id.');

/// The Markdown a task description can show (the description editor's).
const _markdownSubset =
    '**bold**, *italic*, ~~struck~~, [text](url), "- " and "1. " list '
    'items, "# " to "### " headings, a blank line between paragraphs; '
    'nothing else';

const _reminderNotMine =
    'Only a task assigned to you can have a reminder (it goes to the '
    'assignee). Assign it to yourself first.';
