import 'package:material_ui/material_ui.dart';

import '../tasks/task.dart' show TaskColumn, defaultColumns;

/// Colors a project can have, by index.
const projectColors = [
  Color(0xFF5B8DEF),
  Color(0xFFE5795B),
  Color(0xFF4FB286),
  Color(0xFFB57EDC),
  Color(0xFFE3B341),
  Color(0xFF4FB3C9),
  Color(0xFFE06C9F),
  Color(0xFF8E9AAF),
];

/// A group of tasks (collection `projects`). Tasks point to it by id.
final class Project {
  const Project({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    this.order = 0,
    this.columns = defaultColumns,
    this.ownerId,
    required this.createdAt,
  });

  /// The profile whose personal project this is (see [Profile]), or null
  /// for a shared (company) project. A personal project shows only to its
  /// owner, at the top of the sidebar.
  final String? ownerId;

  bool get isPersonal => ownerId != null;

  final String id;
  final String name;

  /// Index into [projectColors].
  final int colorIndex;

  /// Position in the sidebar (ascending).
  final double order;

  /// The columns of this project's board, left to right. Never empty.
  final List<TaskColumn> columns;

  final DateTime createdAt;

  /// The column a task with [status] shows in: that column, or the first
  /// one if this board doesn't have it (deleted, or never placed here).
  String columnFor(String status) =>
      columns.any((c) => c.id == status) ? status : columns.first.id;

  Color get color => projectColors[colorIndex % projectColors.length];

  Project copyWith({
    String? name,
    int? colorIndex,
    double? order,
    List<TaskColumn>? columns,
  }) => Project(
    id: id,
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
    order: order ?? this.order,
    columns: columns ?? this.columns,
    ownerId: ownerId,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'colorIndex': colorIndex,
    'order': order,
    'columns': [
      for (final c in columns) {'id': c.id, 'name': c.title},
    ],
    'ownerId': ownerId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory Project.fromJson(String id, Map<String, Object?> json) => Project(
    id: id,
    name: json['name'] as String? ?? 'Untitled',
    colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
    order: (json['order'] as num?)?.toDouble() ?? 0,
    columns: _columnsFrom(json),
    ownerId: json['ownerId'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// Reads a project's columns. Projects saved before columns could be
/// added and removed have the default ones, with any names they gave them
/// (`columnNames`). Malformed entries are skipped; an empty list falls back
/// to the defaults, since a board always has a column.
List<TaskColumn> _columnsFrom(Map<String, Object?> json) {
  if (json['columns'] case final List stored) {
    final seen = <String>{};
    final columns = [
      for (final c in stored)
        if (c case {'id': final String id, 'name': final String name})
          if (id.isNotEmpty && name.trim().isNotEmpty && seen.add(id))
            TaskColumn(id, name),
    ];
    if (columns.isNotEmpty) return columns;
  }
  final names = json['columnNames'];
  return [
    for (final c in defaultColumns)
      if (names is Map &&
          names[c.id] is String &&
          (names[c.id] as String).trim().isNotEmpty)
        TaskColumn(c.id, names[c.id] as String)
      else
        c,
  ];
}

/// The [projects] whose name matches what's typed in an "Add project" box,
/// ignoring case and surrounding spaces: names starting with [query] first,
/// then ones containing it, each group in the given (sidebar) order. An
/// empty query matches every project.
List<Project> projectSuggestions(Iterable<Project> projects, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [...projects];
  final starts = <Project>[], contains = <Project>[];
  for (final p in projects) {
    final name = p.name.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(p);
    } else if (name.contains(q)) {
      contains.add(p);
    }
  }
  return [...starts, ...contains];
}

/// The projects [profileId] sees: every shared project, plus their own
/// personal one (other profiles' personal projects are hidden).
List<Project> visibleProjects(Iterable<Project> projects, String? profileId) =>
    [
      for (final p in projects)
        if (p.ownerId == null || p.ownerId == profileId) p,
    ];
