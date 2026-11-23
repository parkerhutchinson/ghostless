import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../profiles/profile_repository.dart';
import '../projects/project.dart';
import '../projects/project_logo.dart';
import '../projects/project_repository.dart';
import '../tasks/task_repository.dart';
import 'exporter.dart';
import 'xlsx.dart';

/// Where an export's data comes from.
final class ExportSources {
  const ExportSources({
    required this.projects,
    required this.tasks,
    required this.profiles,
  });
  final ProjectRepository projects;
  final TaskRepository tasks;
  final ProfileRepository profiles;
}

/// Settings' Export section: tick the projects to export, then save them
/// as CSV (one table), Excel (a tab per project; Google Sheets imports it
/// too) or JSON.
class ExportSection extends StatefulWidget {
  const ExportSection({super.key, required this.sources});
  final ExportSources sources;

  @override
  State<ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends State<ExportSection> {
  /// The projects this profile can see, in sidebar order.
  late final List<Project> _projects = visibleProjects(
    widget.sources.projects.current(),
    widget.sources.profiles.current?.id,
  );

  /// The ticked ones (ids); all of them to start with.
  late final Set<String> _chosen = {for (final p in _projects) p.id};

  /// What the last export did, shown under the buttons.
  String? _message;

  ExportData _data() {
    final profiles = widget.sources.profiles.all();
    return ExportData(
      projects: [
        for (final p in _projects)
          if (_chosen.contains(p.id)) p,
      ],
      tasks: widget.sources.tasks.current(),
      profileNames: {for (final p in profiles) p.id: p.displayName},
      projectNames: {
        for (final p in widget.sources.projects.current()) p.id: p.name,
      },
      exportedAt: DateTime.now(),
    );
  }

  /// Asks where to save, then writes [contents] (text or bytes) there.
  /// The saved file's name, or null when cancelled or it failed.
  Future<String?> _save(String extension, String label, Object contents) async {
    final data = _data();
    final location = await getSaveLocation(
      suggestedName: exportFileName(data.projects, DateTime.now(), extension),
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: [extension]),
      ],
    );
    if (location == null) return null; // Cancelled.
    final file = File(location.path);
    try {
      switch (contents) {
        case final List<int> bytes:
          await file.writeAsBytes(bytes);
        default:
          await file.writeAsString('$contents');
      }
    } on FileSystemException catch (e) {
      _say('Couldn’t save it: ${e.osError?.message ?? e.message}');
      return null;
    }
    final name = location.path.split('/').last;
    _say('Saved $name');
    return name;
  }

  Future<void> _csv() => _save('csv', 'CSV', toCsv(exportRows(_data())));

  Future<void> _excel() =>
      _save('xlsx', 'Excel workbook', toXlsx(exportSheets(_data())));

  Future<void> _json() => _save('json', 'JSON', toJson(_data()));

  void _say(String message) {
    if (mounted) setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final none = _chosen.isEmpty;
    final all = _chosen.length == _projects.length;
    Widget button(String label, IconData icon, Future<void> Function() run) =>
        OutlinedButton.icon(
          onPressed: none ? null : run,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colors.text,
            side: BorderSide(color: context.colors.formBorder),
          ),
          icon: Icon(icon, size: 16),
          label: Text(label),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Row(
          children: [
            Text(
              'Export',
              style: TextStyle(fontSize: 12, color: context.colors.text),
            ),
            const Spacer(),
            if (_projects.length > 1)
              TextButton(
                onPressed: () => setState(() {
                  if (all) {
                    _chosen.clear();
                  } else {
                    _chosen.addAll([for (final p in _projects) p.id]);
                  }
                }),
                child: Text(all ? 'Select none' : 'Select all'),
              ),
          ],
        ),
        if (_projects.isEmpty)
          Text(
            'No projects to export.',
            style: TextStyle(fontSize: 13, color: context.colors.mutedText),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              borderRadius: formRadius,
              border: Border.all(color: context.colors.formBorder),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final p in _projects)
                  InkWell(
                    onTap: () => setState(() {
                      if (!_chosen.remove(p.id)) _chosen.add(p.id);
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        spacing: 8,
                        children: [
                          Checkbox(
                            value: _chosen.contains(p.id),
                            shape: formShape,
                            activeColor: scheme.primary,
                            checkColor: scheme.onPrimary,
                            side: BorderSide(
                              color: context.colors.mutedText,
                              width: 1.5,
                            ),
                            onChanged: (on) => setState(() {
                              if (on ?? false) {
                                _chosen.add(p.id);
                              } else {
                                _chosen.remove(p.id);
                              }
                            }),
                          ),
                          ProjectIcon(project: p, size: 14),
                          Expanded(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // Across the full width, each the same size.
        Row(
          spacing: 8,
          children: [
            for (final b in [
              button('CSV', Symbols.table_view, _csv),
              button('Excel', Symbols.grid_on, _excel),
              button('JSON', Symbols.data_object, _json),
            ])
              Expanded(child: b),
          ],
        ),
        if (_message case final message?)
          Text(
            message,
            style: TextStyle(fontSize: 12.5, color: context.colors.mutedText),
          ),
      ],
    );
  }
}
