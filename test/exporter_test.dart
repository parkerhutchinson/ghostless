import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:codename/export/exporter.dart';
import 'package:codename/export/xlsx.dart';
import 'package:codename/projects/project.dart';
import 'package:codename/tasks/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026, 11, 1, 9);
  final a = Project(id: 'a', name: 'Alpha', createdAt: created);
  final b = Project(id: 'b', name: 'Beta', createdAt: created);

  final tasks = [
    Task(
      id: 't2',
      title: 'Second',
      status: 'todo',
      order: 2,
      originId: 'a',
      projectIds: const ['a'],
      createdAt: created,
    ),
    Task(
      id: 't1',
      title: 'First, with "quotes"',
      description: 'Line one\nLine two',
      status: 'todo',
      order: 1,
      tags: const ['bug', 'ui'],
      originId: 'a',
      projectIds: const ['a', 'b'],
      placements: const {'b': (status: 'done', order: 0)},
      completedIn: const {'b'},
      subtasks: const [
        Subtask(id: 's1', title: 'Do it', done: true),
        Subtask(id: 's2', title: 'Check it'),
      ],
      assigneeId: 'p1',
      dueDate: DateTime(2026, 12, 3),
      dueTime: 14 * 60 + 30,
      createdAt: created,
    ),
    Task(
      id: 't3',
      title: 'Elsewhere',
      originId: 'c',
      projectIds: const ['c'],
      createdAt: created,
    ),
  ];

  ExportData data(List<Project> projects) => ExportData(
    projects: projects,
    tasks: tasks,
    profileNames: const {'p1': 'Sam Lee'},
    projectNames: const {'a': 'Alpha', 'b': 'Beta', 'c': 'Gamma'},
    exportedAt: created,
  );

  test('rows: one per task per chosen project, in board order', () {
    final rows = exportRows(data([a, b]));
    expect(rows.first, exportColumns);
    expect(
      [for (final r in rows.skip(1)) (r[0], r[2])],
      [
        ('Alpha', 'First, with "quotes"'),
        ('Alpha', 'Second'),
        ('Beta', 'First, with "quotes"'),
      ],
    );
    // Gamma wasn't chosen: its task isn't in.
    expect(rows.any((r) => r[2] == 'Elsewhere'), isFalse);
  });

  test('a row has the task\'s place and state in that project', () {
    final rows = exportRows(data([a, b]));
    Map<String, String> row(int i) => {
      for (final (j, name) in exportColumns.indexed) name: rows[i][j],
    };
    final inAlpha = row(1), inBeta = row(3);
    expect(inAlpha['Column'], 'To do');
    expect(inAlpha['Completed'], 'No');
    expect(inAlpha['Origin project'], '');
    expect(inBeta['Column'], 'Done');
    expect(inBeta['Completed'], 'Yes');
    expect(inBeta['Origin project'], 'Alpha');
    expect(inAlpha['Assignee'], 'Sam Lee');
    expect(inAlpha['Due date'], '2026-12-03');
    expect(inAlpha['Due time'], '14:30');
    expect(inAlpha['Labels'], 'bug, ui');
    expect(inAlpha['Subtasks'], '[x] Do it\n[ ] Check it');
    expect(inAlpha['Subtasks done'], '1/2');
  });

  test('CSV quotes commas, quotes and line breaks', () {
    final csv = toCsv([
      ['plain', 'a,b', 'say "hi"', 'two\nlines'],
    ]);
    expect(csv, '﻿plain,"a,b","say ""hi""","two\nlines"\r\n');
  });

  test(
    'JSON is an array of projects, each with its columns, labels and tasks',
    () {
      final projects = jsonDecode(toJson(data([b]))) as List;
      expect(projects, hasLength(1));
      final beta = projects.single as Map<String, Object?>;
      expect(beta['name'], 'Beta');
      expect(
        [for (final c in beta['columns']! as List) c['name']],
        ['To do', 'In progress', 'Done'],
      );
      expect(
        [for (final l in beta['labels']! as List) l['name']],
        ['bug', 'ui'],
      );
      final task = (beta['tasks']! as List).single as Map<String, Object?>;
      expect(task['column'], 'done');
      expect(task['completed'], isTrue);
      expect(task['assignee'], {'id': 'p1', 'name': 'Sam Lee'});
      expect(task['subtasks'], [
        {'title': 'Do it', 'done': true},
        {'title': 'Check it', 'done': false},
      ]);
    },
  );

  test('file name: the project\'s, made safe, or "Projects"', () {
    final day = DateTime(2026, 11, 22);
    expect(
      exportFileName(
        [Project(id: 'x', name: 'Q4/Plan', createdAt: created)],
        day,
        'csv',
      ),
      'Q4-Plan 2026-11-22.csv',
    );
    expect(exportFileName([a, b], day, 'json'), 'Projects 2026-11-22.json');
  });

  test('a workbook tab per project, without the Project column', () {
    final sheets = exportSheets(data([a, b]));
    expect([for (final s in sheets) s.name], ['Alpha', 'Beta']);
    expect(sheets.first.rows.first, exportColumns.sublist(1));
    expect(
      [for (final r in sheets.first.rows.skip(1)) r.first],
      ['To do', 'To do'],
    );
    expect(sheets.last.rows, hasLength(2)); // Header + one task.
  });

  test('xlsx: a zip with a worksheet per tab, text escaped', () {
    final bytes = toXlsx([
      (
        name: 'One',
        rows: [
          ['Task', 'Notes'],
          ['a < b & "c"', 'two\nlines'],
        ],
      ),
      (name: 'Two', rows: const <List<String>>[]),
    ]);
    final zip = ZipDecoder().decodeBytes(bytes);
    String file(String path) => utf8.decode(zip.findFile(path)!.content);
    expect(file('xl/workbook.xml'), contains('<sheet name="One"'));
    expect(file('xl/workbook.xml'), contains('<sheet name="Two"'));
    final sheet = file('xl/worksheets/sheet1.xml');
    expect(sheet, contains('<c r="B2"'));
    expect(sheet, contains('a &lt; b &amp; &quot;c&quot;'));
    expect(sheet, contains('two\nlines'));
    expect(zip.findFile('xl/worksheets/sheet2.xml'), isNotNull);
  });

  test('tab names: valid for Excel and distinct', () {
    expect(
      xlsxSheetNames([
        'Q1/Q2: [plan]?',
        'A' * 40,
        'Same',
        'same',
        '',
        "'quoted'",
      ]),
      ['Q1-Q2- -plan--', 'A' * 31, 'Same', 'same (2)', 'Sheet', 'quoted'],
    );
  });

  test('column letters', () {
    expect([0, 25, 26, 27, 701, 702].map(xlsxColumn), [
      'A',
      'Z',
      'AA',
      'AB',
      'ZZ',
      'AAA',
    ]);
  });
}
