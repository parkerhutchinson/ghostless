import 'dart:convert';

import '../projects/project.dart';
import '../tasks/due_date.dart';
import '../tasks/label_colors.dart';
import '../tasks/task.dart';
import 'xlsx.dart';

/// What an export covers: the chosen [projects] (in sidebar order), every
/// task, assignee names by profile id, and every project's name by id (for
/// a task's origin, which may not be one of the chosen).
///
/// A task multi-homed in several chosen projects is listed under each one,
/// in its column there.
final class ExportData {
  const ExportData({
    required this.projects,
    required this.tasks,
    this.profileNames = const {},
    this.projectNames = const {},
    required this.exportedAt,
  });

  final List<Project> projects;
  final List<Task> tasks;
  final Map<String, String> profileNames;
  final Map<String, String> projectNames;
  final DateTime exportedAt;

  /// [project]'s tasks in board order: by column, then position.
  List<Task> tasksIn(Project project) {
    final columnIndex = {for (final (i, c) in project.columns.indexed) c.id: i};
    final tasks = [
      for (final t in this.tasks)
        if (t.isIn(project.id)) t,
    ];
    int column(Task t) =>
        columnIndex[t.placementIn(project.id).status] ?? columnIndex.length;
    tasks.sort((a, b) {
      final byColumn = column(a).compareTo(column(b));
      return byColumn != 0
          ? byColumn
          : a
                .placementIn(project.id)
                .order
                .compareTo(b.placementIn(project.id).order);
    });
    return tasks;
  }
}

/// The spreadsheet's columns, in order.
const exportColumns = [
  'Project',
  'Column',
  'Task',
  'Description',
  'Completed',
  'Assignee',
  'Due date',
  'Due time',
  'Labels',
  'Subtasks',
  'Subtasks done',
  'Origin project',
  'Created',
  'Task ID',
];

/// One row per task per chosen project, under a header row.
List<List<String>> exportRows(ExportData data) => [
  exportColumns,
  for (final project in data.projects)
    for (final t in data.tasksIn(project)) _row(data, project, t),
];

List<String> _row(ExportData data, Project project, Task t) {
  final columns = {for (final c in project.columns) c.id: c.title};
  final status = t.placementIn(project.id).status;
  return [
    project.name,
    columns[status] ?? status,
    t.title,
    t.description,
    t.isCompletedIn(project.id) ? 'Yes' : 'No',
    data.profileNames[t.assigneeId] ?? '',
    t.dueDate == null ? '' : formatDay(t.dueDate!),
    t.dueDate == null || t.dueTime == null ? '' : formatStoredTime(t.dueTime!),
    t.tags.join(', '),
    // One per line, checked off like a list: "[x] Done one".
    [for (final s in t.subtasks) '[${s.done ? 'x' : ' '}] ${s.title}']
        .join('\n'),
    t.subtasks.isEmpty
        ? ''
        : '${t.subtasks.where((s) => s.done).length}/${t.subtasks.length}',
    // Blank when this is its origin.
    t.originId == project.id
        ? ''
        : data.projectNames[t.originId] ??
              [
                for (final p in data.projects)
                  if (p.id == t.originId) p.name,
              ].firstOrNull ??
              '',
    t.createdAt.toUtc().toIso8601String(),
    t.id,
  ];
}

/// A workbook tab per chosen project, named for it: its tasks as rows
/// (without the Project column, which the tab's name gives).
List<XlsxSheet> exportSheets(ExportData data) => [
  for (final project in data.projects)
    (
      name: project.name,
      rows: [
        for (final row in [
          exportColumns,
          for (final t in data.tasksIn(project)) _row(data, project, t),
        ])
          row.sublist(1),
      ],
    ),
];

/// [rows] as CSV (RFC 4180): commas between fields, CRLF between rows, and
/// a field quoted when it has a comma, quote or line break. Starts with a
/// byte order mark so Excel reads it as UTF-8.
String toCsv(List<List<String>> rows) =>
    '﻿${rows.map((r) => r.map(_csvField).join(',')).join('\r\n')}\r\n';

String _csvField(String v) =>
    v.contains(RegExp('[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// Everything chosen as JSON: an array of projects, each with its columns,
/// labels (and their colors) and an array of its tasks; readable without
/// this app.
String toJson(ExportData data) {
  String hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  final palette = labelPalette;
  final json = [
    for (final p in data.projects)
      {
        'id': p.id,
        'name': p.name,
        'color': hex(
          projectColors[p.colorIndex % projectColors.length].toARGB32(),
        ),
        'personal': p.ownerId != null,
        'columns': [
          for (final c in p.columns) {'id': c.id, 'name': c.title},
        ],
        'labels': [
          for (final l in _labelsOf(data, p))
            {
              'name': l,
              'color': hex(
                palette[(p.labelColors[l.toLowerCase()] ??
                            defaultLabelColor(l)) %
                        palette.length]
                    .toARGB32(),
              ),
            },
        ],
        'tasks': [
          for (final t in data.tasksIn(p))
            {
              'id': t.id,
              'title': t.title,
              'description': t.description,
              'column': t.placementIn(p.id).status,
              'completed': t.isCompletedIn(p.id),
              'assignee': switch (t.assigneeId) {
                final id? => {'id': id, 'name': data.profileNames[id]},
                null => null,
              },
              'dueDate': t.dueDate == null ? null : formatDay(t.dueDate!),
              'dueTime': t.dueDate == null || t.dueTime == null
                  ? null
                  : formatStoredTime(t.dueTime!),
              'labels': t.tags,
              'subtasks': [
                for (final s in t.subtasks) {'title': s.title, 'done': s.done},
              ],
              'originProjectId': t.originId,
              'projectIds': t.projectIds,
              'createdAt': t.createdAt.toUtc().toIso8601String(),
            },
        ],
      },
  ];
  return const JsonEncoder.withIndent('  ').convert(json);
}

/// [p]'s labels: kept on it, then any only on its tasks; one per spelling
/// ignoring case.
List<String> _labelsOf(ExportData data, Project p) {
  final byKey = <String, String>{};
  for (final l in p.labels) {
    byKey.putIfAbsent(l.toLowerCase(), () => l);
  }
  for (final t in data.tasks) {
    if (!t.isIn(p.id)) continue;
    for (final l in t.tags) {
      byKey.putIfAbsent(l.toLowerCase(), () => l);
    }
  }
  return byKey.values.toList();
}

/// A file name for an export of [projects] on [day]: the project's name
/// when there's one, else "Projects".
String exportFileName(List<Project> projects, DateTime day, String extension) {
  final base = projects.length == 1
      ? projects.single.name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-').trim()
      : 'Projects';
  return '${base.isEmpty ? 'Export' : base} ${formatDay(day)}.$extension';
}
